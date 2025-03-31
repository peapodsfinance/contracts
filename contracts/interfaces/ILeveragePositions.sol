// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

// import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "erc721a/contracts/interfaces/IERC721A.sol";

interface ILeveragePositions is IERC721A {
    function mint(address receiver) external returns (uint256 tokenId);
}
