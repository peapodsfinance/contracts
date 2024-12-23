// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IVotingPool.sol";
import "../TokenRewards.sol";

contract VotingPool is IVotingPool, ERC20, Ownable {
    using SafeERC20 for IERC20;

    uint256 constant PRECISION = 10 ** 18;

    address public immutable override REWARDS;
    uint256 public override lockupPeriod = 7 days;

    // asset contract => Asset
    mapping(address => Asset) public assets;
    // user => asset => State
    mapping(address => mapping(address => Stake)) public stakes;

    constructor(address _rewardsBeacon, address _rewardsImp, bytes memory _immutables)
        ERC20("Peapods Voting", "vlPEAS")
        Ownable(_msgSender())
    {
        bytes memory _tokenRewardsData = abi.encodeWithSelector(
            IInitializeSelector(_rewardsImp).initializeSelector(), address(this), address(this), false, _immutables
        );
        REWARDS = address(new BeaconProxy(_rewardsBeacon, _tokenRewardsData));
    }

    function processPreSwapFeesAndSwap() external override {
        // NOOP
    }

    function stake(address _asset, uint256 _amount) external override {
        require(_amount > 0, "A");
        IERC20(_asset).safeTransferFrom(_msgSender(), address(this), _amount);
        stakes[_msgSender()][_asset].lastStaked = block.timestamp;
        stakes[_msgSender()][_asset].lockupPeriod = lockupPeriod;
        _updateUserState(_msgSender(), _asset, _amount);
        emit AddStake(_msgSender(), _asset, _amount);
    }

    function unstake(address _asset, uint256 _amount) external override {
        require(_amount > 0, "R");
        Stake storage _stake = stakes[_msgSender()][_asset];
        require(block.timestamp > _stake.lastStaked + _stake.lockupPeriod, "LU");
        uint256 _amtStakeToRemove = (_amount * _stake.stakedToOutputDenomenator) / _stake.stakedToOutputFactor;
        _stake.amtStaked -= _amtStakeToRemove;
        _burn(_msgSender(), _amount);
        IERC20(_asset).safeTransfer(_msgSender(), _amtStakeToRemove);
        emit Unstake(_msgSender(), _asset, _amount, _amtStakeToRemove);
    }

    function update(address _asset) external returns (uint256 _convFctr, uint256 _convDenom) {
        return _updateUserState(_msgSender(), _asset, 0);
    }

    function _updateUserState(address _user, address _asset, uint256 _addAmt)
        internal
        returns (uint256 _convFctr, uint256 _convDenom)
    {
        require(assets[_asset].enabled, "E");
        (_convFctr, _convDenom) = _getConversionFactorAndDenom(_asset);
        Stake storage _stake = stakes[_user][_asset];
        uint256 _den = _stake.stakedToOutputDenomenator > 0 ? _stake.stakedToOutputDenomenator : PRECISION;
        uint256 _mintedAmtBefore = (_stake.amtStaked * _stake.stakedToOutputFactor) / _den;
        _stake.amtStaked += _addAmt;
        _stake.stakedToOutputFactor = _convFctr;
        _stake.stakedToOutputDenomenator = _convDenom;
        uint256 _finalNewMintAmt = (_stake.amtStaked * _convFctr) / _convDenom;
        if (_finalNewMintAmt > _mintedAmtBefore) {
            _mint(_user, _finalNewMintAmt - _mintedAmtBefore);
        } else if (_mintedAmtBefore > _finalNewMintAmt) {
            if (_mintedAmtBefore - _finalNewMintAmt > balanceOf(_user)) {
                _burn(_user, balanceOf(_user));
            } else {
                _burn(_user, _mintedAmtBefore - _finalNewMintAmt);
            }
        }
        emit UpdateUserState(_user, _asset, _convFctr, _convDenom);
    }

    function addOrUpdateAsset(address _asset, IStakingConversionFactor _convFactor, bool _enabled) external onlyOwner {
        assets[_asset] = Asset({enabled: _enabled, convFactor: _convFactor});
    }

    function enableAsset(address _asset) external onlyOwner {
        require(!assets[_asset].enabled, "T");
        assets[_asset].enabled = true;
    }

    function disableAsset(address _asset) external onlyOwner {
        require(assets[_asset].enabled, "T");
        assets[_asset].enabled = false;
    }

    function setLockupPeriod(uint256 _newLockup) external onlyOwner {
        require(_newLockup <= 112 days, "M"); // 16 weeks
        lockupPeriod = _newLockup;
    }

    function _getConversionFactorAndDenom(address _asset) internal view returns (uint256 _factor, uint256 _denom) {
        _factor = PRECISION;
        _denom = PRECISION;
        if (address(assets[_asset].convFactor) != address(0)) {
            (_factor, _denom) = assets[_asset].convFactor.getConversionFactor(_asset);
        }
    }

    function _update(address _from, address _to, uint256 _value) internal override {
        super._update(_from, _to, _value);
        require(_from == address(0) || _to == address(0), "NT");
        if (_from != address(0)) {
            TokenRewards(REWARDS).setShares(_from, _value, true);
        }
        if (_to != address(0) && _to != address(0xdead)) {
            TokenRewards(REWARDS).setShares(_to, _value, false);
        }
    }
}
