// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;
import "forge-std/Test.sol";
import {
    ERC721
} from "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {NFTMarketplace} from "../src/NFTMarketplace.sol";

contract MockNFT is ERC721 {
    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to_, uint256 tokenId_) external {
        _mint(to_, tokenId_);
    }
}

contract NFTMarketplaceTest is Test {
    NFTMarketplace marketplace;
    MockNFT nft;
    address deployer = vm.addr(1);
    address user = vm.addr(2);
    uint256 tokenId = 0;

    function setUp() public {
        vm.startPrank(deployer);
        marketplace = new NFTMarketplace();
        nft = new MockNFT();
        vm.stopPrank();

        vm.startPrank(user);
        nft.mint(user, tokenId);
        vm.stopPrank();
    }

    // Verify contracts deployed and NFT minted to user
    function testMarketplaceDeployed() public view {
        address marketplaceAddress = address(marketplace);
        assertNotEq(marketplaceAddress, address(0));
    }

    function testNFTDeployed() public view {
        address nftAddress = address(nft);
        assertNotEq(nftAddress, address(0));
    }

    function testMintNFT() public view {
        address owner = nft.ownerOf(tokenId);
        assertEq(owner, user);
    }

    //----------------------------

    // Admin tests
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

    function testupdateMarketplaceFeeKO_feeSetToZero() public {
        vm.startPrank(deployer);
        uint256 newFee_ = 0;

        vm.expectRevert("Fee can't be 0");
        marketplace.updateMarketplaceFee(newFee_);

        vm.stopPrank();
    }

    function testupdateMarketplaceFeeKO_notAdmin() public {
        vm.startPrank(user);
        uint256 newFee_ = 0;

        vm.expectRevert();
        marketplace.updateMarketplaceFee(newFee_);

        vm.stopPrank();
    }

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

    function testWithdrawFeesKO_noFeesAvailable() public {
        vm.startPrank(deployer);

        vm.expectRevert();
        marketplace.withdrawFees();

        vm.stopPrank();
    }

    function testWithdrawFeesKO_onlyAdmin() public {
        vm.startPrank(user);

        vm.expectRevert();
        marketplace.withdrawFees();

        vm.stopPrank();
    }

    //----------------------------
    // Listing test
    function testListItemOK() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 price_ = 1 ether;
        uint256 tokenId_ = tokenId;

        (
            address nftAddressBefore_,
            uint256 tokenIdBefore_,
            uint256 priceBefore_,
            address sellerBefore_
        ) = marketplace.listings(nftAddress_, tokenId_);

        marketplace.listItem(nftAddress_, tokenId_, price_);

        (
            address nftAddressAfter_,
            uint256 tokenIdAfter_,
            uint256 priceAfter_,
            address sellerAfter_
        ) = marketplace.listings(nftAddress_, tokenId_);

        //Default values
        assertEq(nftAddressBefore_, address(0));
        assertEq(tokenIdBefore_, 0);
        assertEq(priceBefore_, 0);
        assertEq(sellerBefore_, address(0));

        //Updated values
        assertEq(nftAddressAfter_, nftAddress_);
        assertEq(tokenIdAfter_, tokenId_);
        assertEq(priceAfter_, price_);
        assertEq(sellerAfter_, user);

        vm.stopPrank();
    }

    function testListItemKO_priceIsZero() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 price_ = 0;
        uint256 tokenId_ = tokenId;

        vm.expectRevert("Price can not be 0.");
        marketplace.listItem(nftAddress_, tokenId_, price_);

        vm.stopPrank();
    }

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

    //----------------------------

    // Update price tests
    function testUpdatePriceListingOK() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 tokenId_ = tokenId;
        uint256 initialPrice_ = 1 ether;
        uint256 newPrice_ = 2 ether;

        marketplace.listItem(nftAddress_, tokenId_, initialPrice_);

        (
            address nftAddressBefore_,
            uint256 tokenIdBefore_,
            uint256 priceBefore_,
            address sellerBefore_
        ) = marketplace.listings(nftAddress_, tokenId_);

        marketplace.updatePriceListing(nftAddress_, tokenId_, newPrice_);

        (
            address nftAddressAfter_,
            uint256 tokenIdAfter_,
            uint256 priceAfter_,
            address sellerAfter_
        ) = marketplace.listings(nftAddress_, tokenId_);

        assertEq(nftAddressBefore_, nftAddress_);
        assertEq(tokenIdBefore_, tokenId_);
        assertEq(priceBefore_, initialPrice_);
        assertEq(sellerBefore_, user);

        assertEq(nftAddressAfter_, nftAddress_);
        assertEq(tokenIdAfter_, tokenId_);
        assertEq(priceAfter_, newPrice_);
        assertEq(sellerAfter_, user);

        vm.stopPrank();
    }

    function testUpdatePriceListingKO_unlistedItem() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 newPrice_ = 2 ether;

        vm.expectRevert();
        marketplace.updatePriceListing(nftAddress_, tokenId, newPrice_);

        vm.stopPrank();
    }

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

    //----------------------------

    // Cancel listing tests
    function testCancelListingOK() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 tokenId_ = tokenId;
        uint256 price_ = 1 ether;

        marketplace.listItem(nftAddress_, tokenId, price_);

        (
            address nftAddressBefore_,
            uint256 tokenIdBefore_,
            uint256 priceBefore_,
            address sellerBefore_
        ) = marketplace.listings(nftAddress_, tokenId_);

        marketplace.cancelListing(nftAddress_, tokenId_);

        (
            address nftAddressAfter_,
            uint256 tokenIdAfter_,
            uint256 priceAfter_,
            address sellerAfter_
        ) = marketplace.listings(nftAddress_, tokenId_);

        // Default values
        assertEq(nftAddressBefore_, nftAddress_);
        assertEq(tokenIdBefore_, tokenId_);
        assertEq(priceBefore_, price_);
        assertEq(sellerBefore_, user);

        // Updated values
        assertEq(nftAddressAfter_, address(0));
        assertEq(tokenIdAfter_, 0);
        assertEq(priceAfter_, 0);
        assertEq(sellerAfter_, address(0));

        vm.stopPrank();
    }

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

    function testCancelListingKO_itemNotOwned() public {
        vm.startPrank(user);
        address nftAddress_ = address(nft);
        uint256 tokenId_ = tokenId;
        uint256 price_ = 1 ether;

        marketplace.listItem(nftAddress_, tokenId, price_);
        vm.stopPrank();

        vm.startPrank(vm.addr(4));

        vm.expectRevert(
            "You can not cancel the listing of an item that's not yours or is not listed."
        );
        marketplace.cancelListing(nftAddress_, tokenId_);

        vm.stopPrank();
    }

    //----------------------------

    // Buy item tests
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

    function testBuyItemKO_unlistedItem() public {
        vm.startPrank(user);
        vm.deal(user, 1 ether);
        address nftAddress_ = address(nft);
        uint256 tokenId_ = tokenId;

        vm.expectRevert("Item not listed.");
        marketplace.buyItem{value: 1 ether}(nftAddress_, tokenId_);

        vm.stopPrank();   
    }

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
}
