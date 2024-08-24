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
    address public FORGE_DELEGATE_IMPLEMENTATION;
    uint256 public totalSupply;
    mapping(bytes32 => bool) public storedCID;
    mapping(cNFTtype => uint256) public typeToTotal;
    mapping(address => uint256) public ownerCurrentSI;
    mapping(address => uint256[]) public ownerBonusCNFTs;
    // (user => index => nftID) | (user => nftID => type(uint256).max - index)
    // so if (user => nftID = 0 || user => index = 0)
    // indicates that nftID doesnt blong to user/doesnt exist
    mapping(address => mapping(uint256 => uint256)) public ownerSpecialsDualMap;
    mapping(uint256 => cNFT) public idToCNFT;
    mapping(address => mapping(cNFTtype => uint256)) public ownerToTotalTypes;

    address private immutable SIGN_PB_GATEWAY;

    uint256 private constant BONUS_FEE = 0.00011 ether;
    uint256 private constant SPECIALS_FEE = 0.00017 ether;
    string private constant IPFS_URL = "https://ipfs.io/ipfs/";
    string[] private CONSTANT_PATHS = [
        //BONUS VOXEL
        "https://ipfs.io/ipfs/QmbPkGZmFtip1PRZiNTTV8Darpg7atLtXN6Y1koWQ4WDiQ",
        //SILVER VOXEL
        "https://ipfs.io/ipfs/QmWMrB1hXxSDWVggh34tCPEuYf31jgdWLmfDuazF4TpR2X",
        //GOLD VOXEL
        "https://ipfs.io/ipfs/QmVuag2U9aGpk8DKZEC8iDxBy8tFhD9DHfBMFX5hfhyddo",
        //DIAMOND VOXEL
        "https://ipfs.io/ipfs/Qmdwtjf42L7M6uzzLaDcPYHwPSC8p6hZ6d3p7Sf6Hdc568"
    ];
    /********************************\
    |-*-*-*-*-*   EVENTS   *-*-*-*-*-|
    \********************************/
    event BatchBonusMint(
        address indexed owner,
        uint256 indexed idFrom,
        uint256 indexed idTo
    );

    event SpecialMint(
        address indexed owner,
        uint256 indexed id,
        string cid,
        cNFTtype t
    );

    /********************************\
    |-*-*-*-*    BUILT-IN    *-*-*-*-|
    \********************************/
    constructor(address signerPublicKeyAsGateway)
        Ownable(msg.sender)
        ERC721("BlockChef Campaign NFT", "BC-CNFT")
    {
        require(
            signerPublicKeyAsGateway != address(0),
            "ZERO_ADDRESS_PROVIDED"
        );

        SIGN_PB_GATEWAY = signerPublicKeyAsGateway;
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

    function oneTimeForgeDelegateeSetter(address implementation)
        external
        onlyOwner
    {
        require(!MINTABLE, "DISABLE_MINTING_FIRST");
        require(implementation != address(0), "ZERO_ADDRESS_PROVIDED");
        require(FORGE_DELEGATE_IMPLEMENTATION == address(0), "SETTELD_BEFORE");

        FORGE_DELEGATE_IMPLEMENTATION = implementation;
    }

    function withrawETH() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /********************************\
    |-*-*-*    ERC721-LOGIC    *-*-*-|
    \********************************/
    function mintSpecial(address to, cNFT memory nft) external payable {
        require(MINTABLE, "NOT_MINTABLE_ANYMORE");
        require(msg.value < SPECIALS_FEE, "PAY_FEE");

        if (to == address(0)) to = msg.sender;
        uint256 validValue = SPECIALS_FEE;

        if (
            balanceOf(to) != 0 ||
            nft.t == cNFTtype.Bonus ||
            bytes(nft.cid).length == 0 ||
            nft.sign.length == 0 ||
            storedCID[keccak256(abi.encodePacked(nft.cid))] ||
            keccak256(abi.encodePacked(nft.cid, to)).recover(nft.sign) !=
            SIGN_PB_GATEWAY
        ) {
            validValue = BONUS_FEE;
            nft = cNFT({t: cNFTtype.Bonus, cid: "", sign: ""});
        }

        totalSupply++;
        ownerToTotalTypes[to][nft.t]++;
        typeToTotal[nft.t]++;
        idToCNFT[totalSupply] = nft;
        _mint(to, totalSupply);

        if (nft.t == cNFTtype.Bonus) ownerBonusCNFTs[to].push(totalSupply);
        else {
            // Only 1 Special per EOA will be signed in Off-chain mechanisms
            storedCID[keccak256(abi.encodePacked(nft.cid))] = true;
            ownerCurrentSI[to] = 1;
            ownerSpecialsDualMap[to][0] = totalSupply;
            ownerSpecialsDualMap[to][totalSupply] = type(uint256).max;
        }

        if (msg.value > validValue) {
            (bool sent, ) = payable(msg.sender).call{
                value: (msg.value - validValue)
            }("");
            require(sent);
        }

        emit SpecialMint(to, totalSupply, nft.cid, nft.t);
    }

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

        emit BatchBonusMint(to, supply + 1, supply + totalMintableCNFTs);

        if (msg.value > validValue) {
            (bool sent, ) = payable(msg.sender).call{
                value: (msg.value - validValue)
            }("");
            require(sent);
        }
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

    /********************************\
    |-*-*   ERC721-FORGE-LOGIC   *-*-|
    \********************************/
    function forgeBonuses() external payable {
        require(
            FORGE_DELEGATE_IMPLEMENTATION != address(0),
            "ZERO_ADDRESS_PROVIDED"
        );

        (bool ok, ) = payable(FORGE_DELEGATE_IMPLEMENTATION).delegatecall("");
        require(ok, "CALL_FAILED");
    }

    /********************************\
    |-*-*-*-*-*    VIEW    *-*-*-*-*-|
    \********************************/
    function hasSpecialCNFT(address account) external view returns (bool) {
        return (ownerToTotalTypes[account][cNFTtype.Diamond] != 0 ||
            ownerToTotalTypes[account][cNFTtype.Gold] != 0 ||
            ownerToTotalTypes[account][cNFTtype.Silver] != 0);
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (ownerOf(id) == address(0)) return "";

        if (
            keccak256(abi.encodePacked(idToCNFT[id].cid)) !=
            keccak256(abi.encodePacked(""))
        ) return string(abi.encodePacked(IPFS_URL, idToCNFT[id].cid));
        else return CONSTANT_PATHS[uint8(idToCNFT[id].t)];
    }
}
