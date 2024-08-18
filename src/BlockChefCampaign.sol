// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

contract BlockChefCNFT is Ownable, ERC721 {
    using ECDSA for bytes32;

    enum cNFTtype {
        Bronze,
        Silver,
        Gold,
        Diamond
    }

    struct cNFT {
        cNFTtype t;
        string cid;
        bytes signature;
    }

    bool public TRANSFER_LOCK;
    uint256 public totalSupply;
    mapping(uint256 => cNFT) public idToCNFT;
    mapping(bytes32 => bool) private storedCID;

    constructor()
        Ownable(msg.sender)
        ERC721("BlockChef Campaign NFT", "BC-CNFT")
    {
        TRANSFER_LOCK = true;
    }

    receive() external payable {}

    function oneTimeTransferUnlocker() external onlyOwner {
        delete TRANSFER_LOCK;
    }

    function withrawETH() external {
        payable(owner()).transfer(address(this).balance);
    }

    function safeMint(address to, cNFT memory nft) external payable {
        if (
            nft.t == cNFTtype.Bronze ||
            bytes(nft.cid).length == 0 ||
            nft.signature.length == 0 ||
            storedCID[keccak256(bytes(nft.cid))] ||
            keccak256(abi.encodePacked(nft.cid)).recover(nft.signature) !=
            owner()
        ) {
            nft.cid = "null";
            nft.signature = "null";
            nft.t = cNFTtype.Bronze;
        }

        idToCNFT[totalSupply] = nft;
        storedCID[keccak256(bytes(nft.cid))] = true;
        _safeMint(to, totalSupply);
        totalSupply++;
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public override {
        require(!TRANSFER_LOCK, "TRANSFER_LOCKED");

        super.transferFrom(from, to, id);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string(abi.encodePacked("https://ipfs.io/ipfs/", idToCNFT[id].cid));
    }
}
