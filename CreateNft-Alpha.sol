// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/common/ERC2981.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract MyNFTCollection1155 is ERC1155URIStorage, ERC2981, Pausable, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;

    Counters.Counter private _tokenIdCounter;

    // Fixed variable
    string public constant CREATED_PLATFORM_NAME = "FameGuild NFT Marketplace";
    address public immutable platfromAddress = 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2;
    uint96 public constant platformMintFee = 25; // Platform fee is 0.25% of price paid by Artist
    uint96 public constant platformPublicMintFee = 250; // Platform fee is 2.5% of price
    address public immutable assetOwner;
    
    // State variable
    string public name;
    string public symbol;
    

    // TokenId data struct and then mapping
    struct TokenData {
        uint256 maxSupply;
        uint256 maxMintAmount;
        uint256 mintedSupply;
        uint256 price; // Price for public minting
    }

    mapping(uint256 => TokenData) public tokenData;

    // Events
    event NFTOwnershipTransfered(address from, address to);
    event NFTMinted(uint256 indexed tokenId, uint256 amount, address to);
    event DefaultRoyaltyFeeUpdated(uint96 newFee);
    event TokenRoyaltyFeeUpdated(uint256 indexed tokenId, uint96 royaltyFee);
    event BaseURIUpdated(string newBaseURI);
    event TokenURIUpdated(uint256 indexed tokenId, string newTokenURI);
    event PriceSet(uint256 indexed tokenId, uint256 price);
    event Earned(address assetOwner, uint256 amount);

    constructor(string memory _name, string memory _symbol, string memory _URI, uint96 _defaultRoyaltyFee) ERC1155(_URI) Ownable(msg.sender){
        name = _name;
        symbol = _symbol;
        assetOwner = msg.sender;
        _setDefaultRoyalty(assetOwner, _defaultRoyaltyFee);
    }

    // Function to mint a new tokenId by owner
    function mintDigitalNftToken(uint256 maxSupply, uint256 maxMintAmount, uint256 price, uint256 mintAmount, string memory tokenURI, uint96 tokenRoyaltyFee) public payable onlyOwner nonReentrant {
        require(bytes(tokenURI).length > 0, "Token URI cannot be empty");

        uint256 baseTotalPrice = price * mintAmount;
        uint256 platformFee = (baseTotalPrice * platformMintFee) / 10000; // Calculate the platform fee
        require(msg.value >= platformFee, "Insufficient payment");

        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();

        tokenData[tokenId] = TokenData(maxSupply, maxMintAmount, mintAmount, price);

        _mint(msg.sender, tokenId, mintAmount, "");
        _setURI(tokenId, tokenURI);
        _setTokenRoyalty(tokenId, msg.sender, tokenRoyaltyFee);

        payable(platfromAddress).transfer(platformFee); // Forward platform fee

        emit NFTMinted(tokenId, mintAmount, msg.sender);
    }

    // Function for public users to mint/buy tokens
    function mintPublicDigitalNftToken(uint256 tokenId, uint256 mintAmount) public payable nonReentrant {
        require(mintAmount <= tokenData[tokenId].maxMintAmount, "Mint amount exceeds max mint limit per transaction");
        require(tokenData[tokenId].mintedSupply + mintAmount <= tokenData[tokenId].maxSupply, "Exceeds max supply");
        uint256 baseTotalPrice = tokenData[tokenId].price * mintAmount;
        uint256 platformFee = (baseTotalPrice * platformPublicMintFee) / 10000; // Calculate the platform fee
        uint256 totalPrice = baseTotalPrice + platformFee; // Add the platform fee to the total price
        require(msg.value >= totalPrice, "Insufficient payment");

        tokenData[tokenId].mintedSupply += mintAmount;
        _mint(msg.sender, tokenId, mintAmount, "");

        // Assuming the contract itself handles forwarding of payments
        payable(platfromAddress).transfer(platformFee); // Forward platform fee
        payable(assetOwner).transfer(msg.value - platformFee); // Forward the rest to the asset owner

        emit NFTMinted(tokenId, mintAmount, msg.sender);
    }

    // Function to set the price
    function setPrice(uint256 tokenId, uint256 _price) public onlyOwner {
        require(tokenData[tokenId].maxSupply > 0, "Token does not exist");
        tokenData[tokenId].price = _price;

        emit PriceSet(tokenId, _price);
    }

    // Ensure URI cannot be set to an empty string
    function setTokenURI(uint256 tokenId, string memory _tokenURI) public onlyOwner {
        require(bytes(_tokenURI).length > 0, "Token URI cannot be empty");
        require(tokenData[tokenId].maxSupply > 0, "Token does not exist");

        _setURI(tokenId, _tokenURI);

        emit TokenURIUpdated(tokenId, _tokenURI);
    }

    // Setting base URI for all token types
    function setBaseURI(string memory newBaseURI) public onlyOwner {
        require(bytes(newBaseURI).length > 0, "Base URI cannot be empty");
        _setURI(newBaseURI);

        emit BaseURIUpdated(newBaseURI);
    }

    // Update the default royalty fee for all tokens
    function setDefaultRoyaltyFee(uint96 newDefaultRoyaltyPercentage) public onlyOwner {
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

    // Allowing the contract owner to transfer the NFT's ownership
    function nftOwnershipTransfer(address newOwner) public onlyOwner {
        require(newOwner != address(0), "New owner cannot be the zero address");
        transferOwnership(newOwner);

        emit NFTOwnershipTransfered(msg.sender, newOwner);
    }

    // Enable the owner to withdraw the contract's balance
    function withdraw() public onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);

        emit Earned(msg.sender, balance);
    }

    // Override supportsInterface to automatically check for ERC1155, ERC2981 support
    function supportsInterface(bytes4 interfaceId) public view override(ERC1155, ERC2981) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
