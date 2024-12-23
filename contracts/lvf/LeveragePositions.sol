// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/utils/Context.sol";
import "erc721a/contracts/ERC721A.sol";

contract LeveragePositions is Context, ERC721A {
    address _controller;

    constructor(string memory _name, string memory _symbol) ERC721A(_name, _symbol) {
        _controller = _msgSender();
    }

    function mint(address _receiver) external returns (uint256 _tokenId) {
        require(_msgSender() == _controller, "AUTH");
        _tokenId = _nextTokenId();
        _mint(_receiver, 1);
    }

    function _startTokenId() internal pure override returns (uint256) {
        return 1;
    }
}
