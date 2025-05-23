// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/NFTMarketplace.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract TestNFT is ERC721, Ownable {
    uint256 private _nextTokenId;

    constructor(address initialOwner)
        ERC721("MyToken", "MTK")
        Ownable(initialOwner)
    {}

    function safeMint(address to) public onlyOwner returns (uint256) {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        return tokenId;
    }
}
// Мок-контракт, який провалює переказ ETH
contract FailingReceiver is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    fallback() external payable {
        revert("ETH transfer failed intentionally");
    }

    receive() external payable {
        revert("ETH transfer failed intentionally");
    }
}

contract NFTMarketplaceTest is Test {
    NFTMarketplace marketplace;
    TestNFT testNFT;

    address buyer;
    address seller;

    event ItemListed(address indexed seller, address indexed nftContract, uint256 indexed tokenId, uint256 price);

    function setUp() public {
        buyer = vm.addr(1);
        seller = vm.addr(2);

        marketplace = new NFTMarketplace();
        testNFT = new TestNFT(address(this));
    }


    function testListItemSuccess() external {
        address user = vm.addr(1);
        uint256 tokenId = testNFT.safeMint(user);

        vm.prank(user);
        testNFT.approve(address(marketplace), tokenId);

        uint256 price = 1 ether;

        vm.expectEmit(true, true, true, true);
        emit NFTMarketplace.ItemListed(user, address(testNFT), tokenId, price);

        vm.prank(user);
        marketplace.listItem(address(testNFT), tokenId, price);

        NFTMarketplace.Listing memory listing = marketplace.getListing(address(testNFT), tokenId);
        assertEq(listing.seller, user);
        assertEq(listing.price, price);
    }

    function test_RevertIfNotListed() external {
        vm.prank(buyer);
        vm.expectRevert(NFTMarketplace.NotListed.selector);
        marketplace.buyItem{value: 1 ether}(address(testNFT), 1);
    }

    function test_RevertIfInsufficientPayment() external {
        // seller мінтить
        uint256 tokenId = testNFT.safeMint(seller);
        // seller апруває
        vm.prank(seller);
        testNFT.approve(address(marketplace), tokenId);
        // seller лістить
        uint256 price = 1 ether;
        vm.prank(seller);
        marketplace.listItem(address(testNFT), tokenId, price);
        // очікуємо помилку, коли buyer купує, але відправляє меншу суму
        vm.prank(buyer);
        vm.expectRevert(NFTMarketplace.InsufficientPayment.selector);
        marketplace.buyItem{value : 0.5 ether}(address(testNFT), tokenId);
    }

    function test_RevertIfNotAnOwner() external { // при покупці, чи овнер нікому нфт свою не передав
        // мінтимо
        uint256 tokenId = testNFT.safeMint(seller);
        // апруваємо
        vm.prank(seller);
        testNFT.approve(address(marketplace), tokenId);
        // лістимо
        uint256 price = 1 ether;
        vm.prank(seller);
        marketplace.listItem(address(testNFT), tokenId, price);
        // імітуємо передачу нфт
        vm.prank(seller);
        testNFT.transferFrom(seller, buyer, tokenId);
        // пробуємо купити, але коли seller вже не є власником 
        vm.prank(buyer);
        vm.expectRevert(NFTMarketplace.NotAnOwner.selector);
        marketplace.buyItem{value : price}(address(testNFT), tokenId);
    }

    function test_RevertIfTransferFailed() external {
        // поганий контракт, який провалює переказ
        FailingReceiver failingSeller = new FailingReceiver();
        // мінт на адресу цього контракту
        uint256 tokenId = testNFT.safeMint(address(failingSeller));
        // апруваємо від імені контракту
        vm.prank(address(failingSeller));
        testNFT.approve(address(marketplace), tokenId);
        // лістимо
        uint256 price = 1 ether;
        vm.prank(address(failingSeller));
        marketplace.listItem(address(testNFT), tokenId, price);
        // спроба покупки і очікуємо revert з TransferFailed
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSelector(NFTMarketplace.TransferFailed.selector));
        marketplace.buyItem{value : price}(address(testNFT), tokenId);
    }

}