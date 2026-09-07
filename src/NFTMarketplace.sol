// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;

import { Ownable } from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import { IERC721 } from "../lib/openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import { ReentrancyGuard } from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

/**
 * @title NFT Marketplace
 * @notice Allows users to list ERC-721 tokens for sale in exchange for native currency.
 * @dev Listed NFTs are not held in escrow by this contract. The users only approve the contract to transfer the NFT when is sold.
 */
contract NFTMarketplace is Ownable, ReentrancyGuard {

    uint256 marketplaceFee;
    uint256 accumulatedFees;

    /** @notice Stores the details of an NFT listed for sale. */
    struct Listing {
        address nftAddress;
        uint256 tokenId;
        uint256 price;
        address seller;
    }

    /** @dev The NFT contract address and token ID uniquely identify a listing. */
    mapping(address => mapping(uint256 => Listing)) listings;

    /** @notice Emitted when an NFT is listed for sale. */
    event ListNFT(address indexed nftAddress_, uint256 indexed tokenId_, uint256 price_, address indexed seller_);

    /** @notice Emitted when a listing is cancelled by its seller. */
    event CancelledListing(address indexed nftAddress_, uint256 indexed tokenId_);

    /** @notice Emitted when a listed NFT is purchased. */
    event ItemBuy(address indexed nftAddress_, uint256 indexed tokenId_, uint256 price_, address indexed seller_);

    /** @notice Emitted when the fee is updated by the admin. */
    event UpdatedFee(uint256 newFee_);

    /** @notice Initializes the marketplace and assigns ownership to the deployer. */
    constructor() Ownable(msg.sender) {
        marketplaceFee = 500;
    }

    /**
     * @notice Lists an ERC-721 token for sale.
     * @dev The caller must own the token and approve this contract to transfer it.
     * @param nftAddress_ The address of the ERC-721 contract.
     * @param tokenId_ The ID of the NFT to list.
     * @param price_ The sale price in the native currency, denominated in wei.
     */
    function listItem(address nftAddress_, uint256 tokenId_, uint256 price_) external {
        address _nftOwner = IERC721(nftAddress_).ownerOf(tokenId_);
        require(price_ > 0, "Price can not be 0.");
        require(_nftOwner == msg.sender, "You do not own this NFT.");

        Listing memory listing_ = Listing({
            nftAddress: nftAddress_,
            tokenId: tokenId_,
            price: price_,
            seller: msg.sender
        });
        listings[nftAddress_][tokenId_] = listing_;
        emit ListNFT(nftAddress_, tokenId_, price_, msg.sender);
    }

    /**
     * @notice Purchases a listed NFT for the exact asking price.
     * @dev The listing is deleted before external calls are made. Reentrancy protection
     * prevents a malicious NFT contract or seller from re-entering this function.
     * @param nftAddress_ The address of the ERC-721 contract.
     * @param tokenId_ The ID of the listed NFT.
     */
    function buyItem(address nftAddress_, uint256 tokenId_) external payable nonReentrant {
        Listing storage listing_ = listings[nftAddress_][tokenId_];
        require(listing_.seller != address(0), "Item not listed.");
        require(msg.value == listing_.price, "Please pay the correct amount for this item.");

        address seller_ = listing_.seller; // save seller address before delete item
        uint256 price_ = listing_.price; // save NFT price before delete item
        delete listings[nftAddress_][tokenId_];
        emit ItemBuy(nftAddress_, tokenId_, msg.value, msg.sender);

        uint256 fee = price_ * marketplaceFee / 10000;
        uint256 valueTransfered = price_ - fee;
        accumulatedFees += fee;

        IERC721(nftAddress_).safeTransferFrom(seller_, msg.sender, tokenId_);
        (bool success, ) = seller_.call { value: valueTransfered } ("");
        require(success, "Transfer ETH failed.");
    }

    /**
     * @notice Updates the asking price of an existing listing.
     * @param nftAddress_ The address of the ERC-721 contract.
     * @param tokenId_ The ID of the listed NFT.
     * @param price_ The new sale price in the native currency, denominated in wei.
     */
    function updatePriceListing(address nftAddress_, uint256 tokenId_, uint256 price_) external {
        Listing storage listing_ = listings[nftAddress_][tokenId_];
        require(listing_.seller == msg.sender, "You can not update the price of an unlisted NFT.");
        require(price_ > 0, "Price can not be 0.");

        listing_.price = price_;
    }

    /**
     * @notice Cancels a listing.
     * @param nftAddress_ The address of the ERC-721 contract.
     * @param tokenId_ The ID of the listed NFT.
     */
    function cancelListing(address nftAddress_, uint256 tokenId_) external {
        require(listings[nftAddress_][tokenId_].seller == msg.sender, "You can not cancel the listing of a NFT that is not listed.");

        delete listings[nftAddress_][tokenId_];
        emit CancelledListing(nftAddress_, tokenId_);
    }

    function updateMarketplaceFee(uint256 newFee_) external onlyOwner {
        require(newFee_ > 0, "Fee can't be 0");
        marketplaceFee = newFee_;
        emit UpdatedFee(newFee_);
    }

    function withdrawFees() external onlyOwner {
        uint256 amount_ = accumulatedFees;
        require(amount_ > 0, "No fees to withdraw.");

        accumulatedFees = 0;

        (bool success, ) = msg.sender.call { value: amount_ } ("");
        require(success, "Withdrawal failed");
    }
}