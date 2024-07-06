// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MyNFTCollection721 is ERC721URIStorage, ERC2981, Pausable, Ownable, ReentrancyGuard {
    
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    // Fixed variable
    string public constant CREATED_PLATFORM_NAME = "FameGuild NFT Marketplace";
    address public immutable platformAddress = 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2;
    uint96 public constant platformMintFee = 300; // Platform fee is 3% of price paid by Artist
    address public immutable assetOwner;
    
    // State variable
    string public baseURI;    
    
    // TokenId data struct and then mapping
    struct TokenData {
        address currentOwner;
        uint256 price; // Price for public minting
        address paymentToken; // Address of the ERC20 token for payment
    }

    mapping(uint256 => TokenData) public tokenData;

    // Events
    event NFTMinted(uint256 indexed tokenId, address to);
    event DefaultRoyaltyFeeUpdated(uint96 newFee);
    event TokenRoyaltyFeeUpdated(uint256 indexed tokenId, uint96 royaltyFee);
    event BaseURIUpdated(string newBaseURI);
    event PriceSet(uint256 indexed tokenId, uint256 price);
    event PaymentTokenSet(uint256 indexed tokenId, address paymentToken);
    event Earned(address assetOwner, uint256 amount);

    // Contract constructor
    constructor(string memory _name, string memory _symbol, string memory _baseURI, uint96 _defaultRoyaltyFee) ERC721(_name,_symbol) Ownable(msg.sender){
        assetOwner = msg.sender;
        baseURI = _baseURI;
        _setDefaultRoyalty(assetOwner, _defaultRoyaltyFee);
    }

    // Function to mint a new tokenId by owner
    function mintDigitalNft(uint256 price, string memory tokenURI, uint96 tokenRoyaltyFee, address paymentToken) 
        public payable onlyOwner nonReentrant returns (uint256) {
        require(bytes(tokenURI).length > 0, "Token URI cannot be empty");

        uint256 platformFee = (price * platformMintFee) / 10000; // Calculate the platform fee

        if (paymentToken == 0x0000000000000000000000000000000000000000) {
            require(msg.value >= platformFee, "Insufficient payment in BTC");
            payable(platformAddress).transfer(platformFee);
        } else {
            IERC20 token = IERC20(paymentToken);
            require(token.allowance(msg.sender, address(this)) >= platformFee, "Insufficient token allowance");
            require(token.balanceOf(msg.sender) >= platformFee, "Insufficient token balance");
            token.transferFrom(msg.sender, platformAddress, platformFee);
        }

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        tokenData[tokenId] = TokenData(msg.sender, price, paymentToken);

        _mint(msg.sender, tokenId);
        _setTokenURI(tokenId, tokenURI);
        _setTokenRoyalty(tokenId, msg.sender, tokenRoyaltyFee);

        emit NFTMinted(tokenId, msg.sender);

        return tokenId;
    }


    // Function to set the price and payment token
    function setPriceAndPaymentToken(uint256 tokenId, uint256 _price, address _paymentToken) public {
        require(tokenData[tokenId].currentOwner == msg.sender, "Not the Owner of the TokenID");
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
    function setDefaultRoyaltyFee(uint96 newDefaultRoyaltyPercentage) public onlyOwner {
        require(newDefaultRoyaltyPercentage <= 10000, "Royalty percentage must be between 0 and 100%");
        _setDefaultRoyalty(assetOwner, newDefaultRoyaltyPercentage);

        emit DefaultRoyaltyFeeUpdated(newDefaultRoyaltyPercentage);
    }

    // Set royalty information for a specific token
    function setTokenRoyalty(uint256 tokenId, uint96 royaltyFee) public {
        require(tokenData[tokenId].currentOwner == msg.sender, "Not the Owner of the TokenID");
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
    function supportsInterface(bytes4 interfaceId) public view override(ERC721URIStorage, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

}
