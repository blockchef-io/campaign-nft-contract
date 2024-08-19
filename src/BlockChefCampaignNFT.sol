// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import {ECDSA} from "openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import {ERC721} from "solmate/tokens/ERC721.sol";

contract BlockChefCampaignNFT is Ownable, ERC721 {
    using ECDSA for bytes32;

    /*******************************\
    |-*-*-*-*-*   TYPES   *-*-*-*-*-|
    \*******************************/
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

    /********************************\
    |-*-*-*-*-*   STATES   *-*-*-*-*-|
    \********************************/
    bool public MINTABLE;
    bool public TRANSFERABLE;
    string public IPFS_URL;
    uint256 public totalSupply;
    mapping(cNFTtype => uint256) public typeToTotal;
    mapping(address => mapping(cNFTtype => uint256)) public ownerToTotalTypes;
    mapping(uint256 => cNFT) public idToCNFT;
    mapping(bytes32 => bool) private storedCID;

    /********************************\
    |-*-*-*-*-*   EVENTS   *-*-*-*-*-|
    \********************************/
    event Mint(
        address indexed owner,
        uint256 indexed id,
        string cid,
        cNFTtype t
    );

    /********************************\
    |-*-*-*-*-*  BUILT-IN  *-*-*-*-*-|
    \********************************/
    constructor(string memory ipfs_url)
        Ownable(msg.sender)
        ERC721("BlockChef Campaign NFT", "BC-CNFT")
    {
        require(bytes(ipfs_url).length != 0, "CHECK_IPFS_URL");

        IPFS_URL = ipfs_url;
        MINTABLE = true;
    }

    receive() external payable {
        mint(msg.sender, cNFT(cNFTtype.Bronze, "", ""));
    }

    /********************************\
    |-*-*-*-*   ONLY-OWNER   *-*-*-*-|
    \********************************/
    function oneTimeMintLocker() external onlyOwner {
        delete MINTABLE;
    }

    function oneTimeTransferUnlocker() external onlyOwner {
        TRANSFERABLE = true;
    }

    function withrawETH() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /********************************\
    |-*-*-*    ERC721-LOGIC    *-*-*-|
    \********************************/
    function mint(address to, cNFT memory nft) public payable {
        require(MINTABLE, "NOT_MINTABLE_ANYMORE");

        if (
            nft.t == cNFTtype.Bronze ||
            bytes(nft.cid).length == 0 ||
            nft.signature.length == 0 ||
            storedCID[keccak256(abi.encodePacked(nft.cid))] ||
            keccak256(abi.encodePacked(nft.cid, msg.sender)).recover(nft.signature) !=
            owner()
        ) nft = cNFT({t: cNFTtype.Bronze, cid: "null", signature: "null"});

        emit Mint(to, totalSupply, nft.cid, nft.t);

        idToCNFT[totalSupply] = nft;
        storedCID[keccak256(bytes(nft.cid))] = true;
        _mint(to, totalSupply);
        ownerToTotalTypes[to][nft.t]++;
        typeToTotal[nft.t]++;
        totalSupply++;
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public override {
        TRANSFERABLE
            ? super.transferFrom(from, to, id)
            : revert("TRANSFER_LOCKED");
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string(abi.encodePacked(IPFS_URL, idToCNFT[id].cid));
    }
}
