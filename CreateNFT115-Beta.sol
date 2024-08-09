// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/extensions/ERC1155URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/common/ERC2981Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
contract MyNFTCollection1155 is Initializable, ERC1155URIStorageUpgradeable, ERC2981Upgradeable, PausableUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using CountersUpgradeable for CountersUpgradeable.Counter;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    CountersUpgradeable.Counter private _tokenIdCounter;

    // Fixed variable
    string public constant CREATED_PLATFORM_NAME = "FameGuild NFT Marketplace";
    address public immutable platformAddress = 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2;
    uint96 public constant platformMintFee = 300; // Platform fee is 3% of price paid by Artist
    uint96 public constant platformPublicMintFee = 500; // Platform fee is 5% of price
    address public assetOwner;
    
    // State variable
    string public name;
    string public symbol;
    string public baseURI;
    
    // TokenId data struct and then mapping
    struct TokenData {
        uint256 maxSupply;
        uint256 maxMintAmount;
        uint256 mintedSupply;
        uint256 price; // Price for public minting
        address paymentToken; // ERC20 token address for payment
    }

    mapping(uint256 => TokenData) public tokenData;

    // Event
    event NFTMinted(uint256 indexed tokenId, uint256 amount, address to);
    event DefaultRoyaltyFeeUpdated(uint96 newFee);
    event TokenRoyaltyFeeUpdated(uint256 indexed tokenId, uint96 royaltyFee);
    event BaseURIUpdated(string newBaseURI);
    event TokenURIUpdated(uint256 indexed tokenId, string newTokenURI);
    event PriceSet(uint256 indexed tokenId, uint256 price);
    event PaymentTokenSet(uint256 indexed tokenId, address tokenAddress);
    event Earned(address assetOwner, uint256 amount);

    // Initializer function to replace constructor
    function initialize(string memory _name, string memory _symbol, string memory _URI, uint96 _defaultRoyaltyFee) public initializer {
        __ERC1155URIStorage_init();
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();
        __ERC2981_init();
        
        name = _name;
        symbol = _symbol;
        assetOwner = msg.sender;
        baseURI = _URI;
        _setDefaultRoyalty(assetOwner, _defaultRoyaltyFee);
    }

    // Function to mint a new tokenId by owner
    function mintDigitalNftToken(
        uint256 maxSupply, 
        uint256 maxMintAmount, 
        uint256 price, 
        uint256 mintAmount, 
        string memory tokenURI, 
        uint96 tokenRoyaltyFee, 
        address paymentToken
    ) 
        public 
        payable 
        onlyOwner 
        nonReentrant 
        returns (uint256) 
    {
        require(mintAmount <= maxMintAmount, "Max mint amount exceeded");
        require(maxMintAmount <= maxSupply, "Max mint amount should be less than max supply");
        require(bytes(tokenURI).length > 0, "Token URI cannot be empty");

        uint256 baseTotalPrice = price * mintAmount;
        uint256 platformFee = (baseTotalPrice * platformMintFee) / 10000; // Calculate the platform fee
        
        if (paymentToken == address(0)) {
            require(msg.value >= platformFee, "Insufficient payment in ETH");
            payable(platformAddress).transfer(platformFee);
        } else {
            IERC20Upgradeable token = IERC20Upgradeable(paymentToken);
            require(token.allowance(msg.sender, address(this)) >= platformFee, "Insufficient token allowance");
            require(token.balanceOf(msg.sender) >= platformFee, "Insufficient token balance");
            token.safeTransferFrom(msg.sender, platformAddress, platformFee);
        }

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        tokenData[tokenId] = TokenData(maxSupply, maxMintAmount, mintAmount, price, paymentToken);

        _mint(msg.sender, tokenId, mintAmount, "");
        _setURI(tokenId, tokenURI);
        _setTokenRoyalty(tokenId, msg.sender, tokenRoyaltyFee);
    
        emit NFTMinted(tokenId, mintAmount, msg.sender);
        
        return tokenId;
    }

    // Function for public users to mint/buy tokens
    function mintPublicDigitalNftToken(uint256 tokenId, uint256 mintAmount) public payable nonReentrant {
        require(mintAmount <= tokenData[tokenId].maxMintAmount, "Mint amount exceeds max mint limit per transaction");
        require(mintAmount > 0, "Mint amount cannot be zero");
        require(tokenData[tokenId].mintedSupply + mintAmount <= tokenData[tokenId].maxSupply, "Exceeds max supply");

        uint256 baseTotalPrice = tokenData[tokenId].price * mintAmount;
        uint256 platformFeeRate = (msg.sender == owner()) ? platformMintFee : platformPublicMintFee;
        uint256 platformFee = (baseTotalPrice * platformFeeRate) / 10000;
        uint256 totalPrice = (msg.sender == owner()) ? platformFee : baseTotalPrice + platformFee;

        if (tokenData[tokenId].paymentToken == address(0)) {
            require(msg.value >= totalPrice, "Insufficient payment");
            payable(platformAddress).transfer(platformFee);
            if (msg.sender != owner()) {
                payable(assetOwner).transfer(baseTotalPrice);
            }
        } else {
            IERC20 paymentToken = IERC20(tokenData[tokenId].paymentToken);
            require(paymentToken.allowance(msg.sender, address(this)) >= totalPrice, "Insufficient token allowance");
            require(paymentToken.balanceOf(msg.sender) >= totalPrice, "Insufficient token balance");

            require(paymentToken.transferFrom(msg.sender, platformAddress, platformFee), "Transfer to platform failed");
            if (msg.sender != owner()) {
                require(paymentToken.transferFrom(msg.sender, assetOwner, baseTotalPrice), "Transfer to asset owner failed");
            }
        }

        _mint(msg.sender, tokenId, mintAmount, "");
        tokenData[tokenId].mintedSupply += mintAmount;

        emit NFTMinted(tokenId, mintAmount, msg.sender);
    }


    // Function to set the price and payment token
    function setPriceAndPaymentToken(uint256 tokenId, uint256 _price, address _paymentToken) public onlyOwner {
        require(tokenData[tokenId].maxSupply > 0, "Token does not exist");
        tokenData[tokenId].price = _price;
        tokenData[tokenId].paymentToken = _paymentToken;

        emit PriceSet(tokenId, _price);
        emit PaymentTokenSet(tokenId, _paymentToken);
    }

    // Setting base URI for all token types
    function setBaseURI(string memory newBaseURI) public onlyOwner {
        require(bytes(newBaseURI).length > 0, "Base URI cannot be empty");
        baseURI = newBaseURI;

        emit BaseURIUpdated(newBaseURI);
    }

    // Update the default royalty fee for all tokens
    function setDefaultRoyaltyFee(uint96 newDefaultRoyaltyPercentage) public onlyOwner nonReentrant {
        require(newDefaultRoyaltyPercentage <= 10000, "Royalty percentage must be between 0 and 100%");
        _setDefaultRoyalty(assetOwner, newDefaultRoyaltyPercentage);

        emit DefaultRoyaltyFeeUpdated(newDefaultRoyaltyPercentage);
    }

    // Set royalty information for a specific token
    function setTokenRoyalty(uint256 tokenId, uint96 royaltyFee) public onlyOwner {
        require(tokenData[tokenId].maxSupply > 0, "Token does not exist");
        require(royaltyFee <= 10000, "Royalty fee must be between 0% and 100%");
        _setTokenRoyalty(tokenId, msg.sender, royaltyFee);

        emit TokenRoyaltyFeeUpdated(tokenId, royaltyFee);
    }

    // Functionality to pause and unpause the contract
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // Enable the owner to withdraw the contract's balance
    function withdraw() public onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);

        emit Earned(msg.sender, balance);
    }

    // Override supportsInterface to automatically check for ERC1155, ERC2981 support
    function supportsInterface(bytes4 interfaceId) public view override(ERC1155Upgradeable, ERC2981Upgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
