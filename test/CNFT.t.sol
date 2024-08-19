// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {BlockChefCampaignNFT} from "../src/BlockChefCampaignNFT.sol";

contract BlockChefCampaignNFTTest is Test {
    BlockChefCampaignNFT private nft;
    string private IPFS_URL = "https://ipfs.io/ipfs/";
    string private TEST_CID = "QmTestCID";
    address private immutable OWNER = vm.addr(OWNER_PK);
    address private immutable USER1 = vm.addr(0x4567);
    address private immutable USER2 = vm.addr(0x89AB);
    uint256 private constant OWNER_PK = 0x0123;

    // Config
    function setUp() external {
        vm.prank(OWNER);
        nft = new BlockChefCampaignNFT(IPFS_URL);
    }

    // Test Constructor
    function test_ConstructorInitialState() external view {
        assertEq(nft.MINTABLE(), true);
        assertEq(nft.TRANSFERABLE(), false);
        assertEq(nft.IPFS_URL(), IPFS_URL);
        assertEq(nft.totalSupply(), 0);
    }

    function test_ConstructorRevertsWithEmptyIPFS() external {
        vm.expectRevert("CHECK_IPFS_URL");
        new BlockChefCampaignNFT("");
    }

    // Test Only Owner
    function test_OnlyOwnerCanLockMinting() external {
        vm.prank(USER1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                USER1
            )
        );
        nft.oneTimeMintLocker();

        vm.prank(OWNER);
        nft.oneTimeMintLocker();
        assertEq(nft.MINTABLE(), false);
    }

    function test_OnlyOwnerCanUnlockTransfers() external {
        vm.prank(USER1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                USER1
            )
        );
        nft.oneTimeTransferUnlocker();

        vm.prank(OWNER);
        nft.oneTimeTransferUnlocker();
        assertEq(nft.TRANSFERABLE(), true);
    }

    function test_OwnerCanWithdrawFunds() external {
        vm.deal(address(nft), 1 ether);

        uint256 initialOwnerBalance = OWNER.balance;

        vm.prank(OWNER);
        nft.withrawETH();
        assertEq(OWNER.balance, initialOwnerBalance + 1 ether);
    }

    // Test Transfer
    function test_TransferFailsWhenLocked() external {
        nft.mint(
            USER1,
            BlockChefCampaignNFT.cNFT(
                BlockChefCampaignNFT.cNFTtype.Bronze,
                "",
                ""
            )
        );

        vm.prank(USER1);
        vm.expectRevert("TRANSFER_LOCKED");
        nft.transferFrom(USER1, USER2, 0);
    }

    function test_TransferSucceedsWhenUnlocked() external {
        nft.mint(
            USER1,
            BlockChefCampaignNFT.cNFT(
                BlockChefCampaignNFT.cNFTtype.Bronze,
                "",
                ""
            )
        );

        vm.prank(OWNER);
        nft.oneTimeTransferUnlocker();

        vm.prank(USER1);
        nft.transferFrom(USER1, USER2, 0);
        assertEq(nft.ownerOf(0), USER2);
    }

    // Test Minting
    function test_MintingWithValidSignature() external {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            OWNER_PK,
            keccak256(bytes(TEST_CID))
        );

        nft.mint(
            USER1,
            BlockChefCampaignNFT.cNFT(
                BlockChefCampaignNFT.cNFTtype.Gold,
                TEST_CID,
                abi.encodePacked(r, s, v) // This MUST be a valid signature
            )
        );
        assertEq(nft.totalSupply(), 1);
        assertEq(nft.ownerOf(0), USER1);
        assertEq(
            nft.tokenURI(0),
            string(abi.encodePacked(nft.IPFS_URL(), TEST_CID))
        );
        (BlockChefCampaignNFT.cNFTtype t, , ) = nft.idToCNFT(0);
        assertEq(uint8(t), uint8(BlockChefCampaignNFT.cNFTtype.Gold));
        //* TODO: expectEmit must be added.
    }

    function test_MintingWithFakeSignature() external {
        nft.mint(
            USER1,
            BlockChefCampaignNFT.cNFT(
                BlockChefCampaignNFT.cNFTtype.Gold,
                TEST_CID,
                hex"bd3351bc23afd50352db04db78f989b2d348b89a8a36a25278bd1bb34dea504f62fae7d264884152699d93cf7f27d63650a5258cc88cfe79996bd4037a2844021c" // This MUST be a fake signature"
            )
        );
        assertEq(
            nft.tokenURI(0),
            string(abi.encodePacked(nft.IPFS_URL(), "null"))
        );
        (BlockChefCampaignNFT.cNFTtype t, , ) = nft.idToCNFT(0);
        assertEq(uint8(t), uint8(BlockChefCampaignNFT.cNFTtype.Bronze));
    }

    function test_MintingFailsWithInvalidSignature() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                ECDSA.ECDSAInvalidSignatureLength.selector,
                5
            )
        );
        nft.mint(
            USER1,
            BlockChefCampaignNFT.cNFT(
                BlockChefCampaignNFT.cNFTtype.Gold,
                TEST_CID,
                hex"1122334455" // This MUST be an invalid signature
            )
        );
    }

    function test_MintingWithAlreadyUsedCID() external {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            OWNER_PK,
            keccak256(bytes(TEST_CID))
        );

        BlockChefCampaignNFT.cNFT memory validCNFT = BlockChefCampaignNFT.cNFT(
            BlockChefCampaignNFT.cNFTtype.Diamond,
            TEST_CID,
            abi.encodePacked(r, s, v) // This MUST be a valid signature
        );

        nft.mint(USER1, validCNFT);
        nft.mint(USER2, validCNFT);
        assertEq(nft.totalSupply(), 2);
        assertEq(nft.ownerOf(1), USER2);
        assertEq(
            nft.tokenURI(1),
            string(abi.encodePacked(nft.IPFS_URL(), "null"))
        );
        (BlockChefCampaignNFT.cNFTtype t, , ) = nft.idToCNFT(1);
        assertEq(uint8(t), uint8(BlockChefCampaignNFT.cNFTtype.Bronze));
    }

    function test_MintingFallbacksToBronze() external {
        (bool ok, ) = address(nft).call("");
        assertEq(ok, true);

        (BlockChefCampaignNFT.cNFTtype t, string memory cid, ) = nft.idToCNFT(
            0
        );
        assertEq(uint8(t), uint8(BlockChefCampaignNFT.cNFTtype.Bronze));
        assertEq(cid, "null");
        assertEq(nft.totalSupply(), 1);
    }

    function test_MintingNotAllowedWhenMintingLocked() external {
        vm.prank(OWNER);
        nft.oneTimeMintLocker();

        vm.expectRevert("NOT_MINTABLE_ANYMORE");
        nft.mint(
            USER1,
            BlockChefCampaignNFT.cNFT(
                BlockChefCampaignNFT.cNFTtype.Bronze,
                "",
                ""
            )
        );
    }
}
