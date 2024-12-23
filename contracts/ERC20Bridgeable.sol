// https://peapods.finance

// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "./interfaces/IERC20Bridgeable.sol";

contract ERC20Bridgeable is ERC20, ERC20Permit, IERC20Bridgeable, Ownable {
    uint256 constant MAX_SUPPLY = 10_000_000 * 10 ** 18;
    mapping(address => bool) public minter;

    event Burn(address indexed wallet, uint256 amount);
    event BurnFrom(address indexed from, address indexed wallet, uint256 amount);
    event Mint(address indexed from, address indexed wallet, uint256 amount);
    event SetMinter(address indexed wallet, bool isMinter);

    modifier onlyMinter() {
        require(minter[_msgSender()], "M");
        _;
    }

    constructor(string memory _name, string memory _symbol)
        ERC20(_name, _symbol)
        ERC20Permit(_name)
        Ownable(_msgSender())
    {}

    function burn(uint256 _amount) external override {
        _burn(_msgSender(), _amount);
        emit Burn(_msgSender(), _amount);
    }

    function burnFrom(address _wallet, uint256 _amount) external override onlyMinter {
        _burn(_wallet, _amount);
        emit BurnFrom(_msgSender(), _wallet, _amount);
    }

    function mint(address _wallet, uint256 _amount) external override onlyMinter {
        require(totalSupply() + _amount <= MAX_SUPPLY, "MAX");
        _mint(_wallet, _amount);
        emit Mint(_msgSender(), _wallet, _amount);
    }

    function setMinter(address _wallet, bool _isMinter) external onlyOwner {
        require(minter[_wallet] != _isMinter, "T");
        minter[_wallet] = _isMinter;
        emit SetMinter(_wallet, _isMinter);
    }
}
