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
        Bonus,
        Silver,
        Gold,
        Diamond
    }

    struct cNFT {
        cNFTtype t;
        string cid;
        bytes sign;
    }

    /********************************\
    |-*-*-*-*-*   STATES   *-*-*-*-*-|
    \********************************/
    bool public MINTABLE;
    string public IPFS_URL;
    uint256 public totalSupply;
    mapping(bytes32 => bool) public storedCID;
    mapping(cNFTtype => uint256) public typeToTotal;
    mapping(address => uint256) public ownerCurrentSI;
    mapping(address => uint256[]) public ownerBonusCNFTs;
    // user => index => nftID | user => nftID => type(uint256).max - index
    // so if (user => nftID = 0 || user => index = 0), indicates that nftID doesnt blong to user
    mapping(address => mapping(uint256 => uint256)) public ownerSpecialsDualMap;
    mapping(uint256 => cNFT) public idToCNFT;
    mapping(address => mapping(cNFTtype => uint256)) public ownerToTotalTypes;

    uint256 public immutable SPECIALS_FEE;
    uint256 public immutable BONUS_FEE;

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
    constructor(
        uint256 sfee,
        uint256 bfee,
        string memory ipfs_url
    ) Ownable(msg.sender) ERC721("BlockChef Campaign NFT", "BC-CNFT") {
        require(bytes(ipfs_url).length != 0, "CHECK_IPFS_URL");
        require(sfee != 0 && bfee != 0, "NONE_ZERO_FEE");

        SPECIALS_FEE = sfee;
        BONUS_FEE = bfee;
        IPFS_URL = ipfs_url;
        MINTABLE = true;
    }

    receive() external payable {
        batchBonusMint(msg.sender);
    }

    /********************************\
    |-*-*-*-*   ONLY-OWNER   *-*-*-*-|
    \********************************/
    function oneTimeMintLocker() external onlyOwner {
        delete MINTABLE;
    }

    function withrawETH() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /********************************\
    |-*-*-*    ERC721-LOGIC    *-*-*-|
    \********************************/
    function batchBonusMint(address to) public payable {
        require(msg.value >= BONUS_FEE, "CHECK_BONUS_FEE");
        require(MINTABLE, "NOT_MINTABLE_ANYMORE");

        if (to == address(0)) to = msg.sender;

        uint256 validValue = msg.value > BONUS_FEE * 50
            ? BONUS_FEE * 50
            : msg.value;
        uint256 surplusage = validValue % BONUS_FEE;
        validValue -= surplusage;

        uint256 supply = totalSupply;
        uint256 totalMintableCNFTs = validValue / BONUS_FEE;

        for (uint256 i = 1; i <= totalMintableCNFTs; ) {
            idToCNFT[i + supply] = cNFT(cNFTtype.Bonus, "", "");
            ownerBonusCNFTs[to].push(i + supply);
            _mint(to, i + supply);

            unchecked {
                i++;
            }
        }

        ownerToTotalTypes[to][cNFTtype.Bonus] += totalMintableCNFTs;
        typeToTotal[cNFTtype.Bonus] += totalMintableCNFTs;
        totalSupply += totalMintableCNFTs;

        if (msg.value > validValue) {
            (bool sent, ) = payable(msg.sender).call{
                value: (msg.value - validValue)
            }("");
            require(sent);
        }
    }

    function mintSpecial(address to, cNFT memory nft) external payable {
        require(MINTABLE, "NOT_MINTABLE_ANYMORE");
        require(msg.value < SPECIALS_FEE, "PAY_FEE");
        require(ownerToTotalCNFTs(to) == 0, "ONE_TIME_EVENT");

        if (to == address(0)) to = msg.sender;

        if (
            nft.t == cNFTtype.Bonus ||
            bytes(nft.cid).length == 0 ||
            nft.sign.length == 0 ||
            storedCID[keccak256(abi.encodePacked(nft.cid))] ||
            keccak256(abi.encodePacked(nft.cid, to)).recover(nft.sign) !=
            owner()
        ) nft = cNFT({t: cNFTtype.Bonus, cid: "Qm", sign: ""});

        totalSupply++;
        ownerToTotalTypes[to][nft.t]++;
        typeToTotal[nft.t]++;
        idToCNFT[totalSupply] = nft;
        _mint(to, totalSupply);

        if (nft.t == cNFTtype.Bonus) ownerBonusCNFTs[to].push(totalSupply);
        else {
            // Only 1 Special per EOA will be signed in Off-chain mechanisms
            storedCID[keccak256(bytes(nft.cid))] = true;
            ownerCurrentSI[to] = 1;
            ownerSpecialsDualMap[to][0] = totalSupply;
            ownerSpecialsDualMap[to][totalSupply] = type(uint256).max;
        }

        if (msg.value > SPECIALS_FEE) {
            (bool sent, ) = payable(msg.sender).call{
                value: (msg.value - SPECIALS_FEE)
            }("");
            require(sent);
        }

        emit Mint(to, totalSupply, nft.cid, nft.t);
    }

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public override {
        require(!MINTABLE, "TRANSFER_LOCKED");
        require(idToCNFT[id].t != cNFTtype.Bonus);

        super.transferFrom(from, to, id);

        ownerToTotalTypes[from][idToCNFT[id].t]--;
        delete ownerSpecialsDualMap[from][
            type(uint256).max - ownerSpecialsDualMap[from][id]
        ];
        delete ownerSpecialsDualMap[from][id];

        ownerToTotalTypes[to][idToCNFT[id].t]++;
        ownerCurrentSI[to]++;
        ownerSpecialsDualMap[to][ownerCurrentSI[to]] = id;
        ownerSpecialsDualMap[to][id] = type(uint256).max - ownerCurrentSI[to];
    }

    function forgeBonuses() external {}

    function tokenURI(uint256 id) public view override returns (string memory) {
        return string(abi.encodePacked(IPFS_URL, idToCNFT[id].cid));
    }

    function ownerToTotalCNFTs(address account) public view returns (uint256) {
        return (ownerToTotalTypes[account][cNFTtype.Diamond] +
            ownerToTotalTypes[account][cNFTtype.Gold] +
            ownerToTotalTypes[account][cNFTtype.Silver] +
            ownerToTotalTypes[account][cNFTtype.Bonus]);
    }

    function hasSpecialCNFT(address account) external view returns (bool) {
        return (ownerToTotalTypes[account][cNFTtype.Diamond] != 0 ||
            ownerToTotalTypes[account][cNFTtype.Gold] != 0 ||
            ownerToTotalTypes[account][cNFTtype.Silver] != 0);
    }
}
