// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

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

    bool public MINTABLE;
    bool public TRANSFERABLE;
    uint256 public totalSupply;
    mapping(cNFTtype => uint256) public typeToTotal;
    mapping(address => mapping(cNFTtype => uint256)) public ownerToTotalTypes;
    mapping(uint256 => cNFT) public idToCNFT;
    mapping(bytes32 => bool) private storedCID;

    event Mint(
        address indexed owner,
        uint256 indexed id,
        string cid,
        cNFTtype t
    );

    constructor()
        Ownable(msg.sender)
        ERC721("BlockChef Campaign NFT", "BC-CNFT")
    {
        MINTABLE = true;
    }

    receive() external payable {}

    function oneTimeMintLocker() external onlyOwner {
        delete MINTABLE;
    }

    function oneTimeTransferUnlocker() external onlyOwner {
        TRANSFERABLE = true;
    }

    function withrawETH() external {
        payable(owner()).transfer(address(this).balance);
    }

    function mint(address to, cNFT memory nft) external payable {
        require(MINTABLE, "NOT_MINTABLE_ANYMORE");

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
        ownerToTotalTypes[to][nft.t]++;
        typeToTotal[nft.t]++;
        totalSupply++;

        emit Mint(to, totalSupply - 1, nft.cid, nft.t);
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public override {
        require(!TRANSFERABLE, "TRANSFER_LOCKED");

        super.transferFrom(from, to, id);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return
            string(abi.encodePacked("https://ipfs.io/ipfs/", idToCNFT[id].cid));
    }
}
