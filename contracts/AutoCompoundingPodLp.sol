// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/interfaces/IERC4626.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v3-core/contracts/libraries/FixedPoint96.sol';
import './interfaces/IDecentralizedIndex.sol';
import './interfaces/IDexAdapter.sol';
import './interfaces/IIndexUtils.sol';
import './interfaces/IRewardsWhitelister.sol';
import './interfaces/IV3TwapUtilities.sol';

contract AutoCompoundingPodLp is IERC4626, ERC20, ERC20Permit, Ownable {
  using SafeERC20 for IERC20;

  struct Pools {
    address pool1;
    address pool2;
  }

  event TokenToPairedLpSwapError(
    address rewardsToken,
    address pairedLpToken,
    uint256 amountIn
  );

  uint256 constant FACTOR = 10 ** 18;
  uint24 constant REWARDS_POOL_FEE = 10000;
  uint256 constant LP_SLIPPAGE = 80; // 8%
  uint256 constant REWARDS_SWAP_SLIPPAGE = 20; // 2%

  IDexAdapter immutable DEX_ADAPTER;
  IV3TwapUtilities immutable V3_TWAP_UTILS;

  IDecentralizedIndex public pod;
  IIndexUtils public indexUtils;
  IRewardsWhitelister public rewardsWhitelister;
  bool public yieldConvEnabled = true;
  uint16 public protocolFee = 50; // 1000 precision
  // token in => token out => swap pool(s)
  mapping(address => mapping(address => Pools)) public swapMaps;

  // inputTkn => outputTkn => amountInOverride
  mapping(address => mapping(address => uint256)) _tokenToPairedSwapAmountInOverride;

  // internal tracking
  uint256 _totalAssets;

  /// @notice can pass _pod as null address and set later if need be
  constructor(
    string memory _name,
    string memory _symbol,
    IDecentralizedIndex _pod,
    IDexAdapter _dexAdapter,
    IIndexUtils _utils,
    IRewardsWhitelister _whitelist,
    IV3TwapUtilities _v3TwapUtilities
  ) ERC20(_name, _symbol) ERC20Permit(_name) {
    DEX_ADAPTER = _dexAdapter;
    V3_TWAP_UTILS = _v3TwapUtilities;
    pod = _pod;
    indexUtils = _utils;
    rewardsWhitelister = _whitelist;
  }

  function asset() external view override returns (address) {
    return _asset();
  }

  function totalAssets() public view override returns (uint256) {
    return _totalAssets;
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
    require(_assets != 0, 'M');

    _processRewardsToPodLp(0, block.timestamp);

    _shares = convertToShares(_assets);
    _totalAssets += _assets;
    IERC20(_asset()).safeTransferFrom(_msgSender(), address(this), _assets);
    _mint(_receiver, _shares);
    emit Deposit(_msgSender(), _receiver, _assets, _shares);
  }

  function maxMint(address) external pure override returns (uint256 maxShares) {
    maxShares = type(uint256).max - 1;
  }

  function previewMint(
    uint256 _shares
  ) external view override returns (uint256 _assets) {
    _assets = convertToAssets(_shares);
  }

  function mint(
    uint256 _shares,
    address _receiver
  ) external override returns (uint256 _assets) {
    _assets = convertToAssets(_shares);
    _deposit(_assets, _receiver);
  }

  function maxWithdraw(
    address _owner
  ) external view override returns (uint256 maxAssets) {
    maxAssets = (balanceOf(_owner) * _cbr()) / FACTOR;
  }

  function previewWithdraw(
    uint256 _assets
  ) external view override returns (uint256 _shares) {
    _shares = convertToShares(_assets);
  }

  function withdraw(
    uint256 _assets,
    address _receiver,
    address
  ) external override returns (uint256 _shares) {
    _shares = convertToShares(_assets);
    _withdraw(_shares, _receiver);
  }

  function maxRedeem(
    address _owner
  ) external view override returns (uint256 _maxShares) {
    _maxShares = balanceOf(_owner);
  }

  function previewRedeem(
    uint256 _shares
  ) external view override returns (uint256 _assets) {
    _assets = convertToAssets(_shares);
  }

  function redeem(
    uint256 _shares,
    address _receiver,
    address
  ) external override returns (uint256 _assets) {
    _assets = _withdraw(_shares, _receiver);
  }

  function processAllRewardsTokensToPodLp(
    uint256 _amountLpOutMin,
    uint256 _deadline
  ) external onlyOwner returns (uint256) {
    return _processRewardsToPodLp(_amountLpOutMin, _deadline);
  }

  function _withdraw(
    uint256 _shares,
    address _receiver
  ) internal returns (uint256 _assets) {
    require(_shares != 0, 'B');

    _processRewardsToPodLp(0, block.timestamp);

    _assets = convertToAssets(_shares);
    _burn(_msgSender(), _shares);
    IERC20(_asset()).safeTransfer(_receiver, _assets);
    _totalAssets -= _assets;
    emit Withdraw(_msgSender(), _receiver, _receiver, _assets, _shares);
  }

  // @notice: assumes underlying vault asset has decimals == 18
  function _cbr() internal view returns (uint256) {
    uint256 _supply = totalSupply();
    return _supply == 0 ? FACTOR : (FACTOR * totalAssets()) / _supply;
  }

  function _asset() internal view returns (address) {
    return pod.lpStakingPool();
  }

  function _assetDecimals() internal view returns (uint8) {
    return IERC20Metadata(_asset()).decimals();
  }

  function _processRewardsToPodLp(
    uint256 _amountLpOutMin,
    uint256 _deadline
  ) internal returns (uint256 _lpAmtOut) {
    if (!yieldConvEnabled) {
      return _lpAmtOut;
    }
    address[] memory _tokens = rewardsWhitelister.getFullWhitelist();
    uint256 _len = _tokens.length;
    for (uint256 _i; _i < _len; _i++) {
      address _token = _tokens[_i];
      uint256 _bal = IERC20(_token).balanceOf(address(this));
      if (_bal == 0) {
        continue;
      }
      uint256 _newLp = _tokenToPodLp(_token, _bal, _amountLpOutMin, _deadline);
      _lpAmtOut += _newLp;
      _totalAssets += _newLp;
    }
  }

  function _tokenToPodLp(
    address _token,
    uint256 _amountIn,
    uint256 _amountLpOutMin,
    uint256 _deadline
  ) internal returns (uint256 _lpAmtOut) {
    uint256 _pairedOut = _tokenToPairedLpToken(_token, _amountIn, 0);
    if (protocolFee > 0) {
      uint256 _pairedFee = (_pairedOut * protocolFee) / 1000;
      IERC20(pod.PAIRED_LP_TOKEN()).safeTransfer(owner(), _pairedFee);
      _pairedOut -= _pairedFee;
    }
    _lpAmtOut = _pairedLpTokenToPodLp(_pairedOut, _amountLpOutMin, _deadline);
  }

  function _tokenToPairedLpToken(
    address _token,
    uint256 _amountIn,
    uint256 _amountOutMin
  ) internal returns (uint256 _amountOut) {
    address _pairedLpToken = pod.PAIRED_LP_TOKEN();
    if (_token == _pairedLpToken) {
      return _amountIn;
    }

    address _rewardsToken = pod.lpRewardsToken();
    if (_token != address(0) && _token != _rewardsToken) {
      return _swap(_token, _pairedLpToken, _amountIn, _amountOutMin);
    }
    uint256 _amountInOverride = _tokenToPairedSwapAmountInOverride[
      _rewardsToken
    ][_pairedLpToken];
    if (_amountInOverride > 0) {
      _amountOutMin = (_amountOutMin * _amountInOverride) / _amountIn;
      _amountIn = _amountInOverride;
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
      _amountOutMin =
        (_amountOutNoSlip * (1000 - REWARDS_SWAP_SLIPPAGE)) /
        1000;
    }
    IERC20(_rewardsToken).safeIncreaseAllowance(
      address(DEX_ADAPTER),
      _amountIn
    );
    try
      DEX_ADAPTER.swapV3Single(
        _rewardsToken,
        _pairedLpToken,
        REWARDS_POOL_FEE,
        _amountIn,
        _amountOutMin,
        address(this)
      )
    returns (uint256 __amountOut) {
      _tokenToPairedSwapAmountInOverride[_rewardsToken][_pairedLpToken] = 0;
      _amountOut = __amountOut;
    } catch {
      _tokenToPairedSwapAmountInOverride[_rewardsToken][_pairedLpToken] =
        _amountIn /
        2;
      IERC20(_rewardsToken).safeDecreaseAllowance(
        address(DEX_ADAPTER),
        _amountIn
      );
      emit TokenToPairedLpSwapError(_rewardsToken, _pairedLpToken, _amountIn);
    }
  }

  function _pairedLpTokenToPodLp(
    uint256 _amountIn,
    uint256 _amountOutMin,
    uint256 _deadline
  ) internal returns (uint256 _amountOut) {
    address _pairedLpToken = pod.PAIRED_LP_TOKEN();
    uint256 _half = _amountIn / 2;
    IERC20(_pairedLpToken).safeIncreaseAllowance(address(DEX_ADAPTER), _half);
    DEX_ADAPTER.swapV2Single(
      _pairedLpToken,
      address(pod),
      _half,
      _amountOutMin,
      address(this)
    );
    uint256 _podAmt = pod.balanceOf(address(this));
    IERC20(pod).safeIncreaseAllowance(address(indexUtils), _podAmt);
    IERC20(_pairedLpToken).safeIncreaseAllowance(address(indexUtils), _half);
    return
      indexUtils.addLPAndStake(
        pod,
        _podAmt,
        _pairedLpToken,
        _half,
        _half,
        LP_SLIPPAGE,
        _deadline
      );
  }

  function _swap(
    address _in,
    address _out,
    uint256 _amountIn,
    uint256 _amountOutMin
  ) internal returns (uint256 _amountOut) {
    Pools memory _swapMap = swapMaps[_in][_out];
    if (_swapMap.pool1 == address(0)) {
      address[] memory _path1 = new address[](2);
      _path1[0] = _in;
      _path1[1] = _out;
      return _swapV2(_path1, _amountIn, _amountOutMin);
    }
    bool _twoHops = _swapMap.pool2 != address(0);
    address _token0 = IUniswapV2Pair(_swapMap.pool1).token0();
    address[] memory _path = new address[](_twoHops ? 3 : 2);
    _path[0] = _in;
    _path[1] = !_twoHops
      ? _out
      : _token0 == _in
        ? IUniswapV2Pair(_swapMap.pool1).token1()
        : _token0;
    if (_twoHops) {
      _path[2] = _out;
    }
    _amountOut = _swapV2(_path, _amountIn, _amountOutMin);
  }

  function _swapV2(
    address[] memory _path,
    uint256 _amountIn,
    uint256 _amountOutMin
  ) internal returns (uint256) {
    address _out = _path.length == 3 ? _path[2] : _path[1];
    uint256 _outBefore = IERC20(_out).balanceOf(address(this));
    IERC20(_path[0]).safeIncreaseAllowance(address(DEX_ADAPTER), _amountIn);
    DEX_ADAPTER.swapV2Single(
      _path[0],
      _path[1],
      _amountIn,
      _amountOutMin,
      address(this)
    );
    return IERC20(_out).balanceOf(address(this)) - _outBefore;
  }

  function setZapMap(
    address _in,
    address _out,
    Pools memory _pools
  ) external onlyOwner {
    swapMaps[_in][_out] = _pools;
  }

  function setPod(IDecentralizedIndex _pod) external onlyOwner {
    require(address(pod) == address(0), 'S');
    pod = _pod;
  }

  function setIndexUtils(IIndexUtils _utils) external onlyOwner {
    indexUtils = _utils;
  }

  function setRewardsWhitelister(IRewardsWhitelister _wl) external onlyOwner {
    rewardsWhitelister = _wl;
  }

  function setYieldConvEnabled(bool _enabled) external onlyOwner {
    require(yieldConvEnabled != _enabled, 'T');
    yieldConvEnabled = _enabled;
  }

  function setProtocolFee(uint16 _newFee) external onlyOwner {
    require(_newFee <= 1000, 'MAX');
    protocolFee = _newFee;
  }
}
