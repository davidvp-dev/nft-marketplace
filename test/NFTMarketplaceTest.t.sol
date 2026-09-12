// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;
import { Test } from "forge-std/Test.sol";
import { ERC721 } from "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import { NFTMarketplace } from "../src/NFTMarketplace.sol";

/// @title Mock NFT
/// @notice Minimal ERC-721 token used by the marketplace tests.
contract MockNFT is ERC721 {
    /// @notice Creates the test NFT collection.
    constructor() ERC721("MockNFT", "MNFT") {}

    /**
     * @notice Mints a token to an address for test setup.
     * @param to_ The address receiving the token.
     * @param tokenId_ The token ID to mint.
     */
    function mint(address to_, uint256 tokenId_) external {
        _mint(to_, tokenId_);
    }
}

/// @title Reverting Seller
/// @notice Test account that rejects native currency payments.
contract RevertingSeller {
    /// @notice Reverts whenever the contract receives native currency.
    receive() external payable {
        revert("Seller rejected payment");
    }
}

/// @title NFT Marketplace Tests
/// @notice Verifies marketplace setup, administration, listings, purchases, and failure cases.
contract NFTMarketplaceTest is Test {
    NFTMarketplace marketplace;
    MockNFT nft;
    address deployer = vm.addr(1);
    address user = vm.addr(2);
    uint256 tokenId = 0;

    /// @notice Deploys the marketplace and test NFT, then mints the initial token.
    function setUp() public {
        vm.startPrank(deployer);
        marketplace = new NFTMarketplace();
        nft = new MockNFT();
        vm.stopPrank();

        vm.startPrank(user);
        nft.mint(user, tokenId);
        vm.stopPrank();
    }

    /// @notice Verifies that the marketplace is deployed.
    function testMarketplaceDeployed() public view {
        address marketplaceAddress = address(marketplace);
        assertNotEq(marketplaceAddress, address(0));
    }

    /// @notice Verifies that the mock NFT collection is deployed.
    function testNFTDeployed() public view {
        address nftAddress = address(nft);
        assertNotEq(nftAddress, address(0));
    }

    /// @notice Verifies that the initial token belongs to the test user.
    function testMintNFT() public view {
        address owner = nft.ownerOf(tokenId);
        assertEq(owner, user);
    }

    /// @notice Verifies that the owner can update the marketplace fee.
    function testupdateMarketplaceFeeOK() public {
        vm.startPrank(deployer);
        uint256 newFee_ = 250;

        uint256 previousFee = marketplace.marketplaceFee();
        marketplace.updateMarketplaceFee(newFee_);
        uint256 updatedFee = marketplace.marketplaceFee();

        assertNotEq(previousFee, updatedFee);
        assertEq(updatedFee, newFee_);

        vm.stopPrank();
    }

    /// @notice Verifies that setting the marketplace fee to zero reverts.
    function testupdateMarketplaceFeeKO_feeSetToZero() public {
        vm.startPrank(deployer);
        uint256 newFee_ = 0;

        vm.expectRevert("Fee can't be 0");
        marketplace.updateMarketplaceFee(newFee_);

        vm.stopPrank();
    }

    /// @notice Verifies that a non-owner cannot update the marketplace fee.
    function testupdateMarketplaceFeeKO_notAdmin() public {
        vm.startPrank(user);
        uint256 newFee_ = 0;

        vm.expectRevert();
        marketplace.updateMarketplaceFee(newFee_);

        vm.stopPrank();
    }

    /// @notice Verifies that the owner can withdraw accumulated sale fees.
    function testWithdrawFeesOK() public {
        // 1. user A lists an item for sale (important to approve the NFT)
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 price_ = 1 ether;
        uint256 tokenId_ = tokenId;
        nft.approve(address(marketplace), tokenId_);
        marketplace.listItem(nftAddress_, tokenId_, price_);
        vm.stopPrank();

        // 2. user B buys the item and fees are accumulated (sending {value: price})
        address buyer = vm.addr(4);
        vm.startPrank(buyer);
        vm.deal(buyer, 1 ether);
        marketplace.buyItem{value: 1 ether}(nftAddress_, tokenId_);
        vm.stopPrank();

        // 3. admin withdraws the accumulated fees
        vm.startPrank(deployer);

        uint256 accumulatedFeesBefore = marketplace.accumulatedFees();
        uint256 balanceBefore = deployer.balance;
        marketplace.withdrawFees();
        uint256 accumulatedFeesAfter = marketplace.accumulatedFees();
        uint256 balanceAfter = deployer.balance;

        assert(accumulatedFeesBefore > accumulatedFeesAfter);
        assertEq(accumulatedFeesAfter, 0);
        assert(balanceAfter > balanceBefore);

        vm.stopPrank();
    }

    /// @notice Verifies that withdrawing with no accumulated fees reverts.
    function testWithdrawFeesKO_noFeesAvailable() public {
        vm.startPrank(deployer);

        vm.expectRevert();
        marketplace.withdrawFees();

        vm.stopPrank();
    }

    /// @notice Verifies that only the owner can withdraw fees.
    function testWithdrawFeesKO_onlyAdmin() public {
        vm.startPrank(user);

        vm.expectRevert();
        marketplace.withdrawFees();

        vm.stopPrank();
    }

    /// @notice Verifies that fee withdrawal reverts when the recipient rejects payment.
    function testWithdrawFeesKO_ethNotAvailable() public {
        // 1. user A lists an item for sale (important to approve the NFT)
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 price_ = 1 ether;
        uint256 tokenId_ = tokenId;
        nft.approve(address(marketplace), tokenId_);
        marketplace.listItem(nftAddress_, tokenId_, price_);
        vm.stopPrank();

        // 2. user B buys the item and fees are accumulated (sending {value: price})
        address buyer = vm.addr(4);
        vm.startPrank(buyer);
        vm.deal(buyer, 1 ether);
        marketplace.buyItem{value: 1 ether}(nftAddress_, tokenId_);
        vm.stopPrank();

        // 3. admin transfers ownership to the contract that's rejecting the ETH
        vm.startPrank(deployer);
        RevertingSeller seller = new RevertingSeller();
        marketplace.transferOwnership(address(seller));
        vm.stopPrank();

        // 4. the new owner tries to withdraw the fees
        vm.startPrank(address(seller));
        vm.expectRevert("Withdrawal failed");
        marketplace.withdrawFees();
        vm.stopPrank();

    }

    /// @notice Verifies that a user can create a listing for an owned NFT.
    function testListItemOK() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 price_ = 1 ether;
        uint256 tokenId_ = tokenId;

        (, , , address sellerBefore_) = marketplace.listings(
            nftAddress_,
            tokenId_
        );

        marketplace.listItem(nftAddress_, tokenId_, price_);

        (, , , address sellerAfter_) = marketplace.listings(
            nftAddress_,
            tokenId_
        );

        //Default values
        assertEq(sellerBefore_, address(0));
        assertEq(sellerAfter_, user);

        vm.stopPrank();
    }

    /// @notice Verifies that listing an NFT at zero price reverts.
    function testListItemKO_priceIsZero() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 price_ = 0;
        uint256 tokenId_ = tokenId;

        vm.expectRevert("Price can not be 0.");
        marketplace.listItem(nftAddress_, tokenId_, price_);

        vm.stopPrank();
    }

    /// @notice Verifies that an address that does not own an NFT cannot list it.
    function testListItemKO_invalidOwner() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 price_ = 1 ether;
        uint256 tokenId_ = tokenId;
        vm.stopPrank();

        address notOwner = vm.addr(3);
        vm.startPrank(notOwner);

        vm.expectRevert("You do not own this NFT.");
        marketplace.listItem(nftAddress_, tokenId_, price_);

        vm.stopPrank();
    }

    /// @notice Verifies that a user cannot list an NFT owned by another user.
    function testListItemKO_invalidNFTOwned() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 price_ = 1 ether;
        address user2 = vm.addr(8);
        uint256 tokenId_ = 1;

        nft.mint(user2, tokenId_);
        vm.expectRevert("You do not own this NFT.");
        marketplace.listItem(nftAddress_, 1, price_);

        vm.stopPrank();
    }

    /// @notice Verifies that the seller can update an existing listing price.
    function testUpdatePriceListingOK() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 tokenId_ = tokenId;
        uint256 initialPrice_ = 1 ether;
        uint256 newPrice_ = 2 ether;

        marketplace.listItem(nftAddress_, tokenId_, initialPrice_);

        (, , uint256 priceBefore_, ) = marketplace.listings(
            nftAddress_,
            tokenId_
        );

        marketplace.updatePriceListing(nftAddress_, tokenId_, newPrice_);

        (, , uint256 priceAfter_, ) = marketplace.listings(
            nftAddress_,
            tokenId_
        );

        assertEq(priceBefore_, initialPrice_);
        assertEq(priceAfter_, newPrice_);

        vm.stopPrank();
    }

    /// @notice Verifies that updating a nonexistent listing reverts.
    function testUpdatePriceListingKO_unlistedItem() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 newPrice_ = 2 ether;

        vm.expectRevert();
        marketplace.updatePriceListing(nftAddress_, tokenId, newPrice_);

        vm.stopPrank();
    }

    /// @notice Verifies that an address other than the seller cannot update a listing.
    function testUpdatePriceListingKO_notSeller() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 tokenId_ = tokenId;
        uint256 initialPrice_ = 1 ether;
        uint256 newPrice_ = 2 ether;

        marketplace.listItem(nftAddress_, tokenId_, initialPrice_);
        vm.stopPrank();

        vm.prank(address(4));

        vm.expectRevert();
        marketplace.updatePriceListing(nftAddress_, tokenId, newPrice_);

        vm.stopPrank();
    }

    /// @notice Verifies that updating a listing to zero price reverts.
    function testUpdatePriceListingKO_priceIsZero() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 initialPrice_ = 1 ether;
        uint256 newPrice_ = 0;

        marketplace.listItem(nftAddress_, tokenId, initialPrice_);
        vm.expectRevert("Price can not be 0.");
        marketplace.updatePriceListing(nftAddress_, tokenId, newPrice_);

        vm.stopPrank();
    }

    /// @notice Verifies that the seller can cancel an existing listing.
    function testCancelListingOK() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 tokenId_ = tokenId;
        uint256 price_ = 1 ether;

        (, , , address sellerBeforeList_) = marketplace.listings(
            nftAddress_,
            tokenId_
        );
        marketplace.listItem(nftAddress_, tokenId, price_);
        (, , , address sellerAfterList_) = marketplace.listings(
            nftAddress_,
            tokenId_
        );

        assertEq(sellerBeforeList_, address(0));
        assertEq(sellerAfterList_, user);

        marketplace.cancelListing(nftAddress_, tokenId_);
        (, , , address sellerAfterCancel_) = marketplace.listings(
            nftAddress_,
            tokenId_
        );
        assertEq(sellerAfterCancel_, address(0));

        vm.stopPrank();
    }

    /// @notice Verifies that cancelling a nonexistent listing reverts.
    function testCancelListingKO_itemNoExists() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 tokenId_ = tokenId;

        vm.expectRevert(
            "You can not cancel the listing of an item that's not yours or is not listed."
        );
        marketplace.cancelListing(nftAddress_, tokenId_);

        vm.stopPrank();
    }

    /// @notice Verifies that an address other than the seller cannot cancel a listing.
    function testCancelListingKO_itemNotOwned() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 tokenId_ = tokenId;
        uint256 price_ = 1 ether;

        marketplace.listItem(nftAddress_, tokenId, price_);
        vm.stopPrank();

        vm.startPrank(vm.addr(4));

        vm.expectRevert("You can not cancel the listing of an item that's not yours or is not listed.");
        marketplace.cancelListing(nftAddress_, tokenId_);

        vm.stopPrank();
    }

    /// @notice Verifies that a buyer receives the NFT and the seller receives the sale proceeds.
    function testBuyItemOK() public {
        // 1. user A lists an item for sale (important to approve the NFT)
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 price_ = 1 ether;
        uint256 tokenId_ = tokenId;
        nft.approve(address(marketplace), tokenId_);
        marketplace.listItem(nftAddress_, tokenId_, price_);
        vm.stopPrank();

        // 2. user B buys the item
        address buyer = vm.addr(4);
        vm.startPrank(buyer);
        vm.deal(buyer, 1 ether);

        // STATE BEFORE
        address previousNftOwner = nft.ownerOf(tokenId_);
        uint256 accumulatedFeesBefore = marketplace.accumulatedFees();

        // BUY ITEM FUNCTION
        marketplace.buyItem{value: 1 ether}(nftAddress_, tokenId_);

        // STATE AFTER
        address newNftOwner = nft.ownerOf(tokenId_);
        uint256 accumulatedFeesAfter = marketplace.accumulatedFees();
        uint256 sellerBalanceAfter = user.balance;

        // ASSERTIONS
        assert(accumulatedFeesAfter > accumulatedFeesBefore);
        assertEq(sellerBalanceAfter, price_ - accumulatedFeesAfter);
        assertEq(previousNftOwner, user);
        assertEq(newNftOwner, buyer);

        vm.stopPrank();
    }

    /// @notice Verifies that purchasing a nonexistent listing reverts.
    function testBuyItemKO_unlistedItem() public {
        vm.startPrank(user);
        vm.deal(user, 1 ether);
        address nftAddress_ = address(nft);
        uint256 tokenId_ = tokenId;

        vm.expectRevert("Item not listed.");
        marketplace.buyItem{value: 1 ether}(nftAddress_, tokenId_);

        vm.stopPrank();
    }

    /// @notice Verifies that purchasing with an incorrect amount reverts.
    function testBuyItemKO_incorrectPriceAmount() public {
        // 1. user A lists an item for sale (important to approve the NFT)
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 price_ = 1 ether;
        uint256 tokenId_ = tokenId;
        nft.approve(address(marketplace), tokenId_);
        marketplace.listItem(nftAddress_, tokenId_, price_);
        vm.stopPrank();

        // 2. user B buys the item
        address buyer = vm.addr(4);
        vm.startPrank(buyer);
        vm.deal(buyer, 1 ether);

        vm.expectRevert("Please pay the correct amount for this item.");
        marketplace.buyItem{value: 0.5 ether}(nftAddress_, tokenId_);

        vm.stopPrank();
    }

    /// @notice Verifies that a seller payment failure reverts the purchase and preserves the listing.
    function testBuyItemKO_sellerPaymentReverts() public {
        RevertingSeller seller = new RevertingSeller();
        uint256 price_ = 1 ether;
        uint256 tokenId_ = 1;
        address nftAddress_ = address(nft);

        nft.mint(address(seller), tokenId_);

        vm.startPrank(address(seller));
        nft.approve(address(marketplace), tokenId_);
        marketplace.listItem(nftAddress_, tokenId_, price_);
        vm.stopPrank();

        address buyer = vm.addr(4);
        vm.deal(buyer, price_);
        vm.prank(buyer);
        vm.expectRevert("Transfer ETH failed.");
        marketplace.buyItem{value: price_}(nftAddress_, tokenId_);

        // verify listing is still active
        (, , uint256 storedPrice_, address _seller) = marketplace.listings(nftAddress_,tokenId_);
        assertEq(_seller, address(seller));
        assertEq(storedPrice_, price_);
        assertEq(nft.ownerOf(tokenId_), address(seller));
    }
}
