// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.21;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";

contract BlockCheftCNFT is ERC721 {
    using Strings for *;

    constructor() ERC721("BlockChef Campaign NFT", "BC-CNFT") {}

    function tokenURI(uint256 id) public view override returns (string memory) {}
}
