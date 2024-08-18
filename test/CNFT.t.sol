// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {Test} from "forge-std/Test.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {BlockChefCampaignNFT} from "../src/BlockChefCampaignNFT.sol";

contract BlockChefCampaignNFTTest is Test {
    BlockChefCampaignNFT private nft;
    address private user1 = address(0x4567);
    address private user2 = address(0x89AB);

    function owner() private returns (address addr, uint256 pk) {
        (addr, pk) = makeAddrAndKey("owner");
    }

    function setUp() public {
        nft = new BlockChefCampaignNFT("https://ipfs.io/ipfs/");
        address _owner;
        (_owner, ) = owner();
        nft.transferOwnership(_owner);
    }

    // Test Constructor
    function test_ConstructorInitialState() external view {
        assertEq(nft.MINTABLE(), true);
        assertEq(nft.TRANSFERABLE(), false);
        assertEq(nft.IPFS_URL(), "https://ipfs.io/ipfs/");
        assertEq(nft.totalSupply(), 0);
    }

    function test_ConstructorRevertsWithEmptyIPFS() external {
        vm.expectRevert("CHECK_IPFS_URL");
        new BlockChefCampaignNFT("");
    }

    // Test Only Owner
    function test_OnlyOwnerCanLockMinting() external {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        nft.oneTimeMintLocker();

        address _owner;
        (_owner, ) = owner();

        vm.prank(_owner);
        nft.oneTimeMintLocker();
        assertEq(nft.MINTABLE(), false);
    }

    function test_OnlyOwnerCanUnlockTransfers() external {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                Ownable.OwnableUnauthorizedAccount.selector,
                user1
            )
        );
        nft.oneTimeTransferUnlocker();

        address _owner;
        (_owner, ) = owner();

        vm.prank(_owner);
        nft.oneTimeTransferUnlocker();
        assertEq(nft.TRANSFERABLE(), true);
    }

    function test_OwnerCanWithdrawFunds() external {
        vm.deal(address(nft), 1 ether);

        address _owner;
        (_owner, ) = owner();

        uint256 initialOwnerBalance = _owner.balance;

        vm.prank(_owner);
        nft.withrawETH();

        assertEq(_owner.balance, initialOwnerBalance + 1 ether);
    }

    // Test Transfer
    function test_TransferFailsWhenLocked() external {
        address _owner;
        (_owner, ) = owner();

        vm.prank(_owner);
        nft.mint(
            user1,
            BlockChefCampaignNFT.cNFT(
                BlockChefCampaignNFT.cNFTtype.Bronze,
                "",
                ""
            )
        );

        vm.prank(user1);
        vm.expectRevert("TRANSFER_LOCKED");
        nft.transferFrom(user1, user2, 0);
    }

    function test_TransferSucceedsWhenUnlocked() external {
        address _owner;
        (_owner, ) = owner();

        vm.prank(_owner);
        nft.mint(
            user1,
            BlockChefCampaignNFT.cNFT(
                BlockChefCampaignNFT.cNFTtype.Bronze,
                "",
                ""
            )
        );

        vm.prank(_owner);
        nft.oneTimeTransferUnlocker();

        vm.prank(user1);
        nft.transferFrom(user1, user2, 0);

        assertEq(nft.ownerOf(0), user2);
    }

    // Test Minting
    function test_MintingWithValidSignature() external {
        uint256 ownerPK;
        (, ownerPK) = owner();
        string memory cid = "QmTestCID";
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPK, keccak256(bytes(cid)));
        // This should be a valid signature
        bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.

        BlockChefCampaignNFT.cNFT memory newCNFT = BlockChefCampaignNFT.cNFT(
            BlockChefCampaignNFT.cNFTtype.Gold,
            cid,
            signature
        );

        vm.prank(user1);
        nft.mint(user1, newCNFT);

        assertEq(nft.totalSupply(), 1);
        assertEq(nft.ownerOf(0), user1);
        assertEq(
            nft.tokenURI(0),
            string(abi.encodePacked(nft.IPFS_URL(), cid))
        );
        (BlockChefCampaignNFT.cNFTtype t,,) = nft.idToCNFT(0);
        assertEq(uint8(t), uint8(BlockChefCampaignNFT.cNFTtype.Gold));
    }

    function test_MintingFailsWithInvalidSignature() external {
        // Preparing an invalid signature and cNFT data
        bytes memory signature = hex"0011223344"; // This should be an invalid signature
        string memory cid = "QmTestCID";
        BlockChefCampaignNFT.cNFT memory invalidCNFT = BlockChefCampaignNFT
            .cNFT(BlockChefCampaignNFT.cNFTtype.Gold, cid, signature);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                ECDSA.ECDSAInvalidSignatureLength.selector,
                5
            )
        );
        nft.mint(user1, invalidCNFT);
    }

    function test_MintingWithAlreadyUsedCID() external {
        uint256 ownerPK;
        (, ownerPK) = owner();
        string memory cid = "QmTestCID";
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPK, keccak256(bytes(cid)));
        // This should be a valid signature
        bytes memory signature = abi.encodePacked(r, s, v); // note the order here is different from line above.

        BlockChefCampaignNFT.cNFT memory newCNFT = BlockChefCampaignNFT.cNFT(
            BlockChefCampaignNFT.cNFTtype.Gold,
            cid,
            signature
        );

        vm.prank(user1);
        nft.mint(user1, newCNFT);

        // Attempt to mint again with the same CID
        nft.mint(user2, newCNFT);

        assertEq(nft.totalSupply(), 2);
        assertEq(nft.ownerOf(1), user2);
        assertEq(
            nft.tokenURI(1),
            string(abi.encodePacked(nft.IPFS_URL(), "null"))
        );
        (BlockChefCampaignNFT.cNFTtype t,,) = nft.idToCNFT(1);
        assertEq(uint8(t), uint8(BlockChefCampaignNFT.cNFTtype.Bronze));
    }

    function test_MintingFallbacksToBronze() external {
        // Invalid CID or signature
        BlockChefCampaignNFT.cNFT memory invalidCNFT = BlockChefCampaignNFT
            .cNFT(BlockChefCampaignNFT.cNFTtype.Gold, "InvalidCID", "");

        address _owner;
        (_owner, ) = owner();

        vm.prank(_owner);
        nft.mint(user1, invalidCNFT);

        (BlockChefCampaignNFT.cNFTtype t, string memory cid, ) = nft.idToCNFT(
            0
        );
        assertEq(uint8(t), uint8(BlockChefCampaignNFT.cNFTtype.Bronze));
        assertEq(cid, "null");
    }

    function test_MintingNotAllowedWhenMintingLocked() external {
        address _owner;
        (_owner, ) = owner();

        vm.prank(_owner);
        nft.oneTimeMintLocker();

        vm.expectRevert("NOT_MINTABLE_ANYMORE");
        nft.mint(
            user1,
            BlockChefCampaignNFT.cNFT(
                BlockChefCampaignNFT.cNFTtype.Gold,
                "CID",
                "sig"
            )
        );
    }
}
