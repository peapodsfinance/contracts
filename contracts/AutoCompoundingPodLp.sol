// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';
import './interfaces/IDecentralizedIndex.sol';
import './interfaces/IDexAdapter.sol';
import './interfaces/IIndexUtils.sol';
import './interfaces/IRewardsWhitelister.sol';
import './interfaces/IV3TwapUtilities.sol';
import './Zapper.sol';

contract AutoCompoundingPodLp is IERC4626, ERC20, ERC20Permit, Zapper {
  using SafeERC20 for IERC20;

  uint256 constant FACTOR = 10 ** 18;
  uint24 constant REWARDS_POOL_FEE = 10000;
  uint256 constant DEFAULT_SLIPPAGE = 100;

  IDecentralizedIndex immutable POD;
  IIndexUtils immutable INDEX_UTILS;
  IRewardsWhitelister immutable REWARDS_WHITELISTER;

  error NotImplemented();

  constructor(
    string memory _name,
    string memory _symbol,
    IDecentralizedIndex _pod,
    IDexAdapter _dexAdapter,
    IIndexUtils _utils,
    IRewardsWhitelister _whitelist,
    IV3TwapUtilities _v3TwapUtilities
  )
    ERC20(_name, _symbol)
    ERC20Permit(_name)
    Zapper(_v3TwapUtilities, _dexAdapter)
  {
    POD = _pod;
    INDEX_UTILS = _utils;
    REWARDS_WHITELISTER = _whitelist;
  }

  function asset() external view override returns (address) {
    return _asset();
  }

  function totalAssets() public view override returns (uint256) {
    return IERC20(_asset()).balanceOf(address(this));
  }

  function convertToShares(
    uint256 _assets
  ) public view override returns (uint256 _shares) {
    return (_assets * FACTOR) / _cbr();
  }

  function convertToAssets(
    uint256 _shares
  ) public view override returns (uint256 _assets) {
    return (_shares * _cbr()) / FACTOR;
  }

  function maxDeposit(
    address
  ) external pure override returns (uint256 maxAssets) {
    return type(uint256).max - 1;
  }

  function previewDeposit(
    uint256 _assets
  ) external view override returns (uint256 _shares) {
    return convertToShares(_assets);
  }

  function deposit(
    uint256 _assets,
    address _receiver
  ) external override returns (uint256 _shares) {
    return _deposit(_assets, _receiver);
  }

  function _deposit(
    uint256 _assets,
    address _receiver
  ) internal returns (uint256 _shares) {
    _shares = convertToShares(_assets);
    IERC20(_asset()).safeTransferFrom(_msgSender(), address(this), _assets);
    _processAllRewardsTokensToPodLp(block.timestamp);

    _mint(_receiver, _shares);
    emit Deposit(_msgSender(), _receiver, _assets, _shares);
  }

  function maxMint(address) external pure override returns (uint256 maxShares) {
    return type(uint256).max - 1;
  }

  function previewMint(
    uint256 _shares
  ) external view override returns (uint256 _assets) {
    return convertToAssets(_shares);
  }

  function mint(uint256, address) external override returns (uint256 _assets) {
    revert NotImplemented();
  }

  function maxWithdraw(
    address _owner
  ) external view override returns (uint256 maxAssets) {
    return (balanceOf(_owner) * _cbr()) / FACTOR;
  }

  function previewWithdraw(
    uint256 _assets
  ) external view override returns (uint256 _shares) {
    return convertToShares(_assets);
  }

  function withdraw(
    uint256,
    address,
    address
  ) external override returns (uint256 _shares) {
    revert NotImplemented();
  }

  function maxRedeem(
    address _owner
  ) external view override returns (uint256 _maxShares) {
    uint256 _assets = IERC20(_asset()).balanceOf(_owner);
    return convertToShares(_assets);
  }

  function previewRedeem(
    uint256 _shares
  ) external view override returns (uint256 _assets) {
    return convertToAssets(_shares);
  }

  function redeem(
    uint256 _shares,
    address _receiver,
    address
  ) external override returns (uint256 _assets) {
    return _withdraw(_shares, _receiver);
  }

  function processAllRewardsTokensToPodLp(
    uint256 _deadline
  ) external onlyOwner returns (uint256) {
    return _processAllRewardsTokensToPodLp(_deadline);
  }

  function _withdraw(
    uint256 _shares,
    address _receiver
  ) internal returns (uint256 _assets) {
    // trigger any pending rewards distro
    IERC20(_asset()).transfer(address(this), 0);
    _processAllRewardsTokensToPodLp(block.timestamp);

    _assets = convertToAssets(_shares);
    _burn(_msgSender(), _shares);
    IERC20(_asset()).safeTransfer(_receiver, _assets);
    emit Withdraw(_msgSender(), _receiver, _receiver, _assets, _shares);
  }

  function _cbr() internal view returns (uint256) {
    return
      (FACTOR * totalAssets() * 10 ** decimals()) /
      totalSupply() /
      10 ** IERC20Metadata(_asset()).decimals();
  }

  function _asset() internal view returns (address) {
    return POD.lpStakingPool();
  }

  function _assetDecimals() internal view returns (uint8) {
    return IERC20Metadata(_asset()).decimals();
  }

  function _processAllRewardsTokensToPodLp(
    uint256 _deadline
  ) internal returns (uint256 _lpAmtOut) {
    address[] memory _tokens = REWARDS_WHITELISTER.getFullWhitelist();
    uint256 _len = _tokens.length;
    for (uint256 _i; _i < _len; _i++) {
      address _token = _tokens[_i];
      uint256 _bal = IERC20(_token).balanceOf(address(this));
      if (_bal == 0) {
        continue;
      }
      // TODO: use oracles to calculate slippage
      _lpAmtOut += _tokenToPodLp(_token, _bal, 0, 0, _deadline);
    }
  }

  function _tokenToPodLp(
    address _token,
    uint256 _amountIn,
    uint256 _amountLpOutMin,
    uint256 _slippageOverride,
    uint256 _deadline
  ) internal returns (uint256 _lpAmtOut) {
    uint256 _pairedOut = _tokenToPairedLpToken(
      _token,
      _amountIn,
      0,
      _slippageOverride
    );
    return _pairedLpTokenToPodLp(_pairedOut, _amountLpOutMin, _deadline);
  }

  function _tokenToPairedLpToken(
    address _token,
    uint256 _amountIn,
    uint256 _amountOutMin,
    uint256 _slippageOverride
  ) internal returns (uint256 _amountOut) {
    address _pairedLpToken = POD.PAIRED_LP_TOKEN();
    address _rewardsToken = POD.lpRewardsToken();
    if (_token != address(0) && _token != _rewardsToken) {
      return _zap(_token, _pairedLpToken, _amountIn, _amountOutMin);
    }
    (address _token0, address _token1) = _pairedLpToken < _rewardsToken
      ? (_pairedLpToken, _rewardsToken)
      : (_rewardsToken, _pairedLpToken);
    address _pool = DEX_ADAPTER.getV3Pool(_token0, _token1, REWARDS_POOL_FEE);
    uint160 _rewardsSqrtPriceX96 = V3_TWAP_UTILS
      .sqrtPriceX96FromPoolAndInterval(_pool);
    uint256 _rewardsPriceX96 = V3_TWAP_UTILS.priceX96FromSqrtPriceX96(
      _rewardsSqrtPriceX96
    );
    if (_amountOutMin == 0) {
      uint256 _amountOutNoSlip = _token0 == _rewardsToken
        ? (_rewardsPriceX96 * _amountIn) / FixedPoint96.Q96
        : (_amountIn * FixedPoint96.Q96) / _rewardsPriceX96;
      uint256 _slippage = _slippageOverride > 0
        ? _slippageOverride
        : DEFAULT_SLIPPAGE;
      _amountOutMin = (_amountOutNoSlip * (1000 - _slippage)) / 1000;
    }
    IERC20(_rewardsToken).safeIncreaseAllowance(
      address(DEX_ADAPTER),
      _amountIn
    );
    return
      DEX_ADAPTER.swapV3Single(
        _rewardsToken,
        _pairedLpToken,
        REWARDS_POOL_FEE,
        _amountIn,
        _amountOutMin,
        address(this)
      );
  }

  function _pairedLpTokenToPodLp(
    uint256 _amountIn,
    uint256 _amountOutMin,
    uint256 _deadline
  ) internal returns (uint256 _amountOut) {
    address _pairedLpToken = POD.PAIRED_LP_TOKEN();
    uint256 _half = _amountIn / 2;
    IERC20(_pairedLpToken).safeIncreaseAllowance(address(DEX_ADAPTER), _half);
    DEX_ADAPTER.swapV2Single(
      _pairedLpToken,
      address(POD),
      _half,
      _amountOutMin,
      address(this)
    );
    return
      INDEX_UTILS.addLPAndStake(
        POD,
        POD.balanceOf(address(this)),
        _pairedLpToken,
        _half,
        _half,
        DEFAULT_SLIPPAGE,
        _deadline
      );
  }
}
