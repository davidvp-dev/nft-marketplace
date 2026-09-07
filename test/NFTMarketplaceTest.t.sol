// SPDX-License-Identifier: MIT

pragma solidity 0.8.34;
import "forge-std/Test.sol";
import { ERC721 } from "../lib/openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import { NFTMarketplace } from "../src/NFTMarketplace.sol";

contract MockNFT is ERC721 {

    constructor() ERC721("MockNFT", "MNFT") {}

    function mint(address to_, uint256 tokenId_) external {
        _mint(to_, tokenId_);
    }
}

contract NFTMarketplaceTest is Test {

    NFTMarketplace marketplace;
    MockNFT mockNFT;
    address deployer = vm.addr(1);
    address user = vm.addr(2);

    function setup() public {
        vm.startPrank(deployer);
        marketplace = new NFTMarketplace();
        vm.stopPrank();

        vm.startPrank(user);
        mockNFT.mint(user, 0);
        vm.stopPrank();
    }

}