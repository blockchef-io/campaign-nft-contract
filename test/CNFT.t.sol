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
    uint256 private constant BONUS_FEE = 0.00011 ether;
    uint256 private constant SPECIALS_FEE = 0.00015 ether;
    address private constant FORGE_TEST_IMPL = address(0x1);

    // Config
    function setUp() external {
        vm.deal(USER1, (10 * SPECIALS_FEE) + (9 * BONUS_FEE) + 1e17);
        vm.deal(USER2, (10 * SPECIALS_FEE) + (9 * BONUS_FEE) + 1e17);

        vm.prank(OWNER);
        nft = new BlockChefCampaignNFT(BONUS_FEE, SPECIALS_FEE, IPFS_URL);
    }

    // Test Constructor
    function test_ConstructorInitialState() external {
        assertEq(nft.BONUS_FEE(), BONUS_FEE);
        assertEq(nft.SPECIALS_FEE(), SPECIALS_FEE);
        assertEq(nft.IPFS_URL(), IPFS_URL);
        assertEq(nft.MINTABLE(), true);
        assertEq(nft.totalSupply(), 0);
        assertEq(nft.owner(), OWNER);
        assertEq(nft.name(), "BlockChef Campaign NFT");
        assertEq(nft.symbol(), "BC-CNFT");
    }

    function test_ConstructorRevertsWithEmptyIPFS() external {
        vm.expectRevert("CHECK_IPFS_URL");
        new BlockChefCampaignNFT(SPECIALS_FEE, BONUS_FEE, "");
    }

    function test_ConstructorRevertsWithZeroFees() external {
        vm.expectRevert("ZERO_FEE_PROVIDED");
        new BlockChefCampaignNFT(BONUS_FEE, 0, IPFS_URL);

        vm.expectRevert("ZERO_FEE_PROVIDED");
        new BlockChefCampaignNFT(0, SPECIALS_FEE, IPFS_URL);
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

    function test_OnlyOwnerCanSetForgeDelegatee() external {
        vm.prank(USER1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                USER1
            )
        );
        nft.oneTimeForgeDelegateeSetter(FORGE_TEST_IMPL);

        vm.startPrank(OWNER);

        vm.expectRevert("DISABLE_MINTING_FIRST");
        nft.oneTimeForgeDelegateeSetter(FORGE_TEST_IMPL);

        nft.oneTimeMintLocker();
        vm.expectRevert("ZERO_ADDRESS_PROVIDED");
        nft.oneTimeForgeDelegateeSetter(address(0));

        nft.oneTimeMintLocker();
        nft.oneTimeForgeDelegateeSetter(FORGE_TEST_IMPL);
        vm.expectRevert("SETTELD_BEFORE");
        nft.oneTimeForgeDelegateeSetter(address(0x2));

        nft.oneTimeMintLocker();
        nft.oneTimeForgeDelegateeSetter(FORGE_TEST_IMPL);
        assertEq(nft.FORGE_DELEGATE_IMPLEMENTATION(), FORGE_TEST_IMPL);

        vm.stopPrank();
    }

    function test_OnlyOwnerCanWithdrawFunds() external {
        uint256 initialOwnerBalance = OWNER.balance;

        vm.deal(address(nft), 1 ether);
        vm.prank(OWNER);
        nft.withrawETH();
        assertEq(OWNER.balance, initialOwnerBalance + 1 ether);
    }

    // Test Transfer
    function test_TransferFailsWhenMintingActive() external {
        vm.prank(OWNER);
        nft.mintSpecial{value: SPECIALS_FEE}(
            USER1,
            BlockChefCampaignNFT.cNFT(
                BlockChefCampaignNFT.cNFTtype.Silver,
                TEST_CID,
                ""
            )
        );

        vm.prank(USER1);
        vm.expectRevert("TRANSFER_LOCKED");
        nft.transferFrom(USER1, USER2, 1);
    }

    function test_TransferSucceedsWhenMintingLocked() external {
        vm.prank(USER1);
        nft.mintSpecial{value: SPECIALS_FEE}(
            USER1,
            BlockChefCampaignNFT.cNFT(
                BlockChefCampaignNFT.cNFTtype.Bonus,
                "",
                ""
            )
        );

        vm.prank(OWNER);
        nft.oneTimeMintLocker();

        vm.prank(USER1);
        nft.transferFrom(USER1, USER2, 1);
        assertEq(nft.ownerOf(1), USER2);
    }

    // Test Minting
    function test_MintingBonus() external {
        vm.prank(USER1);
        nft.batchBonusMint{value: BONUS_FEE}(USER1);
        assertEq(nft.totalSupply(), 1);
        assertEq(nft.ownerOf(1), USER1);
        (BlockChefCampaignNFT.cNFTtype t, , ) = nft.idToCNFT(1);
        assertEq(uint8(t), uint8(BlockChefCampaignNFT.cNFTtype.Bonus));
    }

    function test_MintingSpecialWithValidSignature() external {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            OWNER_PK,
            keccak256(
                abi.encodePacked(bytes(TEST_CID), bytes20(address(USER1)))
            )
        );

        vm.prank(USER1);
        nft.mintSpecial{value: SPECIALS_FEE}(
            USER1,
            BlockChefCampaignNFT.cNFT(
                BlockChefCampaignNFT.cNFTtype.Gold,
                TEST_CID,
                abi.encodePacked(r, s, v) // This MUST be a valid signature
            )
        );
        assertEq(nft.totalSupply(), 1);
        assertEq(nft.ownerOf(1), USER1);
        assertEq(
            nft.tokenURI(1),
            string(abi.encodePacked(nft.IPFS_URL(), TEST_CID))
        );
        (BlockChefCampaignNFT.cNFTtype t, , ) = nft.idToCNFT(1);
        assertEq(uint8(t), uint8(BlockChefCampaignNFT.cNFTtype.Gold));
    }

    function test_MintingSpecialWithInvalidSignature() external {
        vm.prank(USER1);
        nft.mintSpecial{value: SPECIALS_FEE}(
            USER1,
            BlockChefCampaignNFT.cNFT(
                BlockChefCampaignNFT.cNFTtype.Gold,
                TEST_CID,
                hex"1122334455" // This MUST be an invalid signature
            )
        );
        assertEq(nft.totalSupply(), 1);
        (BlockChefCampaignNFT.cNFTtype t, , ) = nft.idToCNFT(1);
        assertEq(uint8(t), uint8(BlockChefCampaignNFT.cNFTtype.Bonus));
    }

    function test_MintingSpecialWithAlreadyUsedCID() external {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            OWNER_PK,
            keccak256(bytes(TEST_CID))
        );

        BlockChefCampaignNFT.cNFT memory validCNFT = BlockChefCampaignNFT.cNFT(
            BlockChefCampaignNFT.cNFTtype.Diamond,
            TEST_CID,
            abi.encodePacked(r, s, v) // This MUST be a valid signature
        );

        vm.prank(USER1);
        nft.mintSpecial{value: SPECIALS_FEE}(USER1, validCNFT);
        vm.prank(USER2);
        nft.mintSpecial{value: SPECIALS_FEE}(USER2, validCNFT);

        assertEq(nft.totalSupply(), 2);
        assertEq(nft.ownerOf(2), USER2);
        assertEq(
            nft.tokenURI(2),
            string(abi.encodePacked(nft.IPFS_URL(), ""))
        );
        (BlockChefCampaignNFT.cNFTtype t, , ) = nft.idToCNFT(2);
        assertEq(uint8(t), uint8(BlockChefCampaignNFT.cNFTtype.Bonus));
    }

    function test_MintingNotAllowedWhenMintingLocked() external {
        vm.prank(OWNER);
        nft.oneTimeMintLocker();

        vm.expectRevert("NOT_MINTABLE_ANYMORE");
        vm.prank(USER1);
        nft.mintSpecial{value: SPECIALS_FEE}(
            USER1,
            BlockChefCampaignNFT.cNFT(
                BlockChefCampaignNFT.cNFTtype.Silver,
                TEST_CID,
                ""
            )
        );
    }
}
