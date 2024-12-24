// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";
import "./interfaces/IDecentralizedIndex.sol";
import "./interfaces/IDexAdapter.sol";
import "./interfaces/IFraxlendPair.sol";
import "./interfaces/IIndexUtils.sol";
import "./interfaces/ISPTknOracle.sol";
import "./interfaces/IStakingPoolToken.sol";
import "./interfaces/ITokenRewards.sol";

contract AutoCompoundingPodLp is IERC4626, ERC20, ERC20Permit, Ownable {
    using SafeERC20 for IERC20;

    struct Pools {
        address pool1;
        address pool2;
    }

    event AddLpAndStakeError(address pod, uint256 amountIn);

    event AddLpAndStakeV2SwapError(address pairedLpToken, address pod, uint256 amountIn);

    event SetIndexUtils(address indexUtils);

    event SetLpSlippage(uint256 slippage);

    event SetMaxSwap(address tokenIn, uint256 maxSwap);

    event SetPod(address pod);

    event SetPodOracle(address oracle);

    event SetProtocolFee(uint16 oldFee, uint16 newFee);

    event SetSwapMap(address tokenIn, address tokenOut);

    event SetYieldConvEnabled(bool enabled);

    event TokenToPairedLpSwapError(address rewardsToken, address pairedLpToken, uint256 amountIn);

    event WithdrawProtocolFees(uint256 feesToPay);

    uint256 constant FACTOR = 10 ** 18;
    uint24 constant REWARDS_POOL_FEE = 10000;
    uint256 constant REWARDS_SWAP_SLIPPAGE = 20; // 2%

    IDexAdapter immutable DEX_ADAPTER;
    bool immutable IS_PAIRED_LENDING_PAIR;

    IDecentralizedIndex public pod;
    IIndexUtils public indexUtils;
    ISPTknOracle public podOracle; // oracle to price pTKN per base for slippage
    bool public yieldConvEnabled = true;
    uint16 public protocolFee = 50; // 1000 precision
    uint256 public lpSlippage = 300;
    // token in => token out => swap pool(s)
    mapping(address => mapping(address => Pools)) public swapMaps;
    // token in => max input amount to swap
    mapping(address => uint256) public maxSwap;

    // inputTkn => outputTkn => amountInOverride
    mapping(address => mapping(address => uint256)) _tokenToPairedSwapAmountInOverride;

    // internal tracking
    uint256 _totalAssets;
    uint256 _protocolFees;

    /// @notice can pass _pod as null address and set later if need be
    constructor(
        string memory _name,
        string memory _symbol,
        bool _isSelfLendingPod,
        IDecentralizedIndex _pod,
        IDexAdapter _dexAdapter,
        IIndexUtils _utils
    ) ERC20(_name, _symbol) ERC20Permit(_name) Ownable(_msgSender()) {
        _setPod(_pod);
        IS_PAIRED_LENDING_PAIR = _isSelfLendingPod;
        DEX_ADAPTER = _dexAdapter;
        indexUtils = _utils;
    }

    function asset() external view override returns (address) {
        return _asset();
    }

    function totalAssets() public view override returns (uint256) {
        return _totalAssets;
    }

    function convertToShares(uint256 _assets) public view override returns (uint256 _shares) {
        return _convertToShares(_assets, Math.Rounding.Floor);
    }

    function _convertToShares(uint256 _assets, Math.Rounding _roundDirection) internal view returns (uint256 _shares) {
        return Math.mulDiv(_assets, FACTOR, _cbr(), _roundDirection);
    }

    function convertToAssets(uint256 _shares) public view override returns (uint256 _assets) {
        return _convertToAssets(_shares, Math.Rounding.Floor);
    }

    function _convertToAssets(uint256 _shares, Math.Rounding _roundDirection) internal view returns (uint256 _assets) {
        return Math.mulDiv(_shares, _cbr(), FACTOR, _roundDirection);
    }

    function maxDeposit(address) external pure override returns (uint256 maxAssets) {
        maxAssets = type(uint256).max;
    }

    function previewDeposit(uint256 _assets) external view override returns (uint256 _shares) {
        return _convertToShares(_assets, Math.Rounding.Floor);
    }

    function deposit(uint256 _assets, address _receiver) external override returns (uint256 _shares) {
        _processRewardsToPodLp(0, block.timestamp);
        _shares = _convertToShares(_assets, Math.Rounding.Floor);
        _deposit(_assets, _shares, _receiver);
    }

    function _deposit(uint256 _assets, uint256 _shares, address _receiver) internal {
        require(_assets != 0, "MA");
        require(_shares != 0, "MS");

        _totalAssets += _assets;
        IERC20(_asset()).safeTransferFrom(_msgSender(), address(this), _assets);
        _mint(_receiver, _shares);
        emit Deposit(_msgSender(), _receiver, _assets, _shares);
    }

    function maxMint(address) external pure override returns (uint256 maxShares) {
        maxShares = type(uint256).max;
    }

    function previewMint(uint256 _shares) external view override returns (uint256 _assets) {
        _assets = _convertToAssets(_shares, Math.Rounding.Ceil);
    }

    function mint(uint256 _shares, address _receiver) external override returns (uint256 _assets) {
        _processRewardsToPodLp(0, block.timestamp);
        _assets = _convertToAssets(_shares, Math.Rounding.Ceil);
        _deposit(_assets, _shares, _receiver);
    }

    function maxWithdraw(address _owner) external view override returns (uint256 maxAssets) {
        maxAssets = (balanceOf(_owner) * _cbr()) / FACTOR;
    }

    function previewWithdraw(uint256 _assets) external view override returns (uint256 _shares) {
        _shares = _convertToShares(_assets, Math.Rounding.Ceil);
    }

    function withdraw(uint256 _assets, address _receiver, address _owner) external override returns (uint256 _shares) {
        _processRewardsToPodLp(0, block.timestamp);
        _shares = _convertToShares(_assets, Math.Rounding.Ceil);
        _withdraw(_assets, _shares, _msgSender(), _owner, _receiver);
    }

    function maxRedeem(address _owner) external view override returns (uint256 _maxShares) {
        _maxShares = balanceOf(_owner);
    }

    function previewRedeem(uint256 _shares) external view override returns (uint256 _assets) {
        _assets = _convertToAssets(_shares, Math.Rounding.Floor);
    }

    function redeem(uint256 _shares, address _receiver, address _owner) external override returns (uint256 _assets) {
        _processRewardsToPodLp(0, block.timestamp);
        _assets = _convertToAssets(_shares, Math.Rounding.Floor);
        _withdraw(_assets, _shares, _msgSender(), _owner, _receiver);
    }

    function processAllRewardsTokensToPodLp(uint256 _amountLpOutMin, uint256 _deadline)
        external
        onlyOwner
        returns (uint256)
    {
        return _processRewardsToPodLp(_amountLpOutMin, _deadline);
    }

    function _withdraw(uint256 _assets, uint256 _shares, address _caller, address _owner, address _receiver) internal {
        require(_shares != 0, "B");

        if (_caller != _owner) {
            _spendAllowance(_owner, _caller, _shares);
        }

        _totalAssets -= _assets;
        _burn(_owner, _shares);
        IERC20(_asset()).safeTransfer(_receiver, _assets);
        emit Withdraw(_owner, _receiver, _receiver, _assets, _shares);
    }

    // @notice: assumes underlying vault asset has decimals == 18
    function _cbr() internal view returns (uint256) {
        uint256 _supply = totalSupply();
        return _supply == 0 ? FACTOR : (FACTOR * totalAssets()) / _supply;
    }

    function _asset() internal view returns (address) {
        return pod.lpStakingPool();
    }

    function _processRewardsToPodLp(uint256 _amountLpOutMin, uint256 _deadline) internal returns (uint256 _lpAmtOut) {
        if (!yieldConvEnabled) {
            return _lpAmtOut;
        }
        address[] memory _tokens = ITokenRewards(IStakingPoolToken(_asset()).POOL_REWARDS()).getAllRewardsTokens();
        uint256 _len = _tokens.length + 1;
        for (uint256 _i; _i < _len; _i++) {
            address _token = _i == _tokens.length ? pod.lpRewardsToken() : _tokens[_i];
            uint256 _bal =
                IERC20(_token).balanceOf(address(this)) - (_token == pod.PAIRED_LP_TOKEN() ? _protocolFees : 0);
            if (_bal == 0) {
                continue;
            }
            uint256 _newLp = _tokenToPodLp(_token, _bal, 0, _deadline);
            _lpAmtOut += _newLp;
        }
        _totalAssets += _lpAmtOut;
        require(_lpAmtOut >= _amountLpOutMin, "M");
    }

    function _tokenToPodLp(address _token, uint256 _amountIn, uint256 _amountLpOutMin, uint256 _deadline)
        internal
        returns (uint256 _lpAmtOut)
    {
        uint256 _pairedOut = _tokenToPairedLpToken(_token, _amountIn);
        if (_pairedOut > 0) {
            uint256 _pairedFee = (_pairedOut * protocolFee) / 1000;
            if (_pairedFee > 0) {
                _protocolFees += _pairedFee;
                _pairedOut -= _pairedFee;
            }
            _lpAmtOut = _pairedLpTokenToPodLp(_pairedOut, _deadline);
            require(_lpAmtOut >= _amountLpOutMin, "M");
        }
    }

    function _tokenToPairedLpToken(address _token, uint256 _amountIn) internal returns (uint256 _amountOut) {
        address _pairedLpToken = pod.PAIRED_LP_TOKEN();
        address _swapOutputTkn = _pairedLpToken;
        if (_token == _pairedLpToken) {
            return _amountIn;
        } else if (maxSwap[_token] > 0 && _amountIn > maxSwap[_token]) {
            _amountIn = maxSwap[_token];
        }

        // if self lending pod, we need to swap for the lending pair borrow token,
        // then deposit into the lending pair which is the paired LP token for the pod
        if (IS_PAIRED_LENDING_PAIR) {
            _swapOutputTkn = IFraxlendPair(_pairedLpToken).asset();
        }

        address _rewardsToken = pod.lpRewardsToken();
        if (_token != _rewardsToken) {
            _amountOut = _swap(_token, _swapOutputTkn, _amountIn, 0);
            if (IS_PAIRED_LENDING_PAIR) {
                _amountOut = _depositIntoLendingPair(_pairedLpToken, _swapOutputTkn, _amountOut);
            }
            return _amountOut;
        }
        uint256 _amountInOverride = _tokenToPairedSwapAmountInOverride[_rewardsToken][_swapOutputTkn];
        if (_amountInOverride > 0) {
            _amountIn = _amountInOverride;
        }
        uint256 _minSwap = 10 ** (IERC20Metadata(_rewardsToken).decimals() / 2);
        _minSwap = _minSwap == 0 ? 10 ** IERC20Metadata(_rewardsToken).decimals() : _minSwap;
        IERC20(_rewardsToken).safeIncreaseAllowance(address(DEX_ADAPTER), _amountIn);
        try DEX_ADAPTER.swapV3Single(
            _rewardsToken,
            _swapOutputTkn,
            REWARDS_POOL_FEE,
            _amountIn,
            0, // _amountOutMin can be 0 because this is nested inside of function with LP slippage provided
            address(this)
        ) returns (uint256 __amountOut) {
            _tokenToPairedSwapAmountInOverride[_rewardsToken][_swapOutputTkn] = 0;
            _amountOut = __amountOut;

            // if this is a self-lending pod, convert the received borrow token
            // into fTKN shares and use as the output since it's the pod paired LP token
            if (IS_PAIRED_LENDING_PAIR) {
                _amountOut = _depositIntoLendingPair(_pairedLpToken, _swapOutputTkn, _amountOut);
            }
        } catch {
            _tokenToPairedSwapAmountInOverride[_rewardsToken][_swapOutputTkn] =
                _amountIn / 2 < _minSwap ? _minSwap : _amountIn / 2;
            IERC20(_rewardsToken).safeDecreaseAllowance(address(DEX_ADAPTER), _amountIn);
            emit TokenToPairedLpSwapError(_rewardsToken, _swapOutputTkn, _amountIn);
        }
    }

    function _depositIntoLendingPair(address _lendingPair, address _pairAsset, uint256 _depositAmt)
        internal
        returns (uint256 _shares)
    {
        IERC20(_pairAsset).safeIncreaseAllowance(address(_lendingPair), _depositAmt);
        _shares = IFraxlendPair(_lendingPair).deposit(_depositAmt, address(this));
    }

    function _pairedLpTokenToPodLp(uint256 _amountIn, uint256 _deadline) internal returns (uint256 _amountOut) {
        address _pairedLpToken = pod.PAIRED_LP_TOKEN();
        uint256 _pairedSwapAmt = _getSwapAmt(_pairedLpToken, address(pod), _pairedLpToken, _amountIn);
        uint256 _pairedRemaining = _amountIn - _pairedSwapAmt;
        uint256 _minPtknOut;
        if (address(podOracle) != address(0)) {
            // calculate the min out with 5% slippage
            _minPtknOut = (
                podOracle.getPodPerBasePrice() * _pairedSwapAmt * 10 ** IERC20Metadata(address(pod)).decimals() * 95
            ) / 10 ** IERC20Metadata(_pairedLpToken).decimals() / 10 ** 18 / 100;
        }
        IERC20(_pairedLpToken).safeIncreaseAllowance(address(DEX_ADAPTER), _pairedSwapAmt);
        try DEX_ADAPTER.swapV2Single(_pairedLpToken, address(pod), _pairedSwapAmt, _minPtknOut, address(this)) returns (
            uint256 _podAmountOut
        ) {
            // reset here to local balances to accommodate any residual leftover from previous runs
            _podAmountOut = pod.balanceOf(address(this));
            _pairedRemaining = IERC20(_pairedLpToken).balanceOf(address(this)) - _protocolFees;
            IERC20(pod).safeIncreaseAllowance(address(indexUtils), _podAmountOut);
            IERC20(_pairedLpToken).safeIncreaseAllowance(address(indexUtils), _pairedRemaining);
            try indexUtils.addLPAndStake(
                pod, _podAmountOut, _pairedLpToken, _pairedRemaining, _pairedRemaining, lpSlippage, _deadline
            ) returns (uint256 _lpTknOut) {
                _amountOut = _lpTknOut;
            } catch {
                IERC20(pod).safeDecreaseAllowance(address(indexUtils), _podAmountOut);
                IERC20(_pairedLpToken).safeDecreaseAllowance(address(indexUtils), _pairedRemaining);
                emit AddLpAndStakeError(address(pod), _amountIn);
            }
        } catch {
            IERC20(_pairedLpToken).safeDecreaseAllowance(address(DEX_ADAPTER), _pairedSwapAmt);
            emit AddLpAndStakeV2SwapError(_pairedLpToken, address(pod), _pairedRemaining);
        }
    }

    function _swap(address _in, address _out, uint256 _amountIn, uint256 _amountOutMin)
        internal
        returns (uint256 _amountOut)
    {
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
        _path[1] = !_twoHops ? _out : _token0 == _in ? IUniswapV2Pair(_swapMap.pool1).token1() : _token0;
        if (_twoHops) {
            _path[2] = _out;
        }
        _amountOut = _swapV2(_path, _amountIn, _amountOutMin);
    }

    function _swapV2(address[] memory _path, uint256 _amountIn, uint256 _amountOutMin)
        internal
        returns (uint256 _amountOut)
    {
        bool _twoHops = _path.length == 3;
        if (maxSwap[_path[0]] > 0 && _amountIn > maxSwap[_path[0]]) {
            _amountOutMin = (_amountOutMin * maxSwap[_path[0]]) / _amountIn;
            _amountIn = maxSwap[_path[0]];
        }
        IERC20(_path[0]).safeIncreaseAllowance(address(DEX_ADAPTER), _amountIn);
        _amountOut =
            DEX_ADAPTER.swapV2Single(_path[0], _path[1], _amountIn, _twoHops ? 0 : _amountOutMin, address(this));
        if (_twoHops) {
            uint256 _intermediateBal = _amountOut > 0 ? _amountOut : IERC20(_path[1]).balanceOf(address(this));
            if (maxSwap[_path[1]] > 0 && _intermediateBal > maxSwap[_path[1]]) {
                _intermediateBal = maxSwap[_path[1]];
            }
            IERC20(_path[1]).safeIncreaseAllowance(address(DEX_ADAPTER), _intermediateBal);
            _amountOut = DEX_ADAPTER.swapV2Single(_path[1], _path[2], _intermediateBal, _amountOutMin, address(this));
        }
    }

    // optimal one-sided supply LP: https://blog.alphaventuredao.io/onesideduniswap/
    function _getSwapAmt(address _t0, address _t1, address _swapT, uint256 _fullAmt) internal view returns (uint256) {
        (uint112 _r0, uint112 _r1) = DEX_ADAPTER.getReserves(DEX_ADAPTER.getV2Pool(_t0, _t1));
        uint112 _r = _swapT == _t0 ? _r0 : _r1;
        return (_sqrt(_r * (_fullAmt * 3988000 + _r * 3988009)) - (_r * 1997)) / 1994;
    }

    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function withdrawProtocolFees() external onlyOwner {
        require(_protocolFees > 0, "Z");
        uint256 _feesToPay = _protocolFees;
        _protocolFees = 0;
        IERC20(pod.PAIRED_LP_TOKEN()).safeTransfer(_msgSender(), _feesToPay);
        emit WithdrawProtocolFees(_feesToPay);
    }

    function setSwapMap(address _in, address _out, Pools memory _pools) external onlyOwner {
        swapMaps[_in][_out] = _pools;
        emit SetSwapMap(_in, _out);
    }

    function setMaxSwap(address _in, uint256 _amt) external onlyOwner {
        maxSwap[_in] = _amt;
        emit SetMaxSwap(_in, _amt);
    }

    function setPod(IDecentralizedIndex _pod) external onlyOwner {
        require(address(_pod) != address(0), "INP");
        _setPod(_pod);
    }

    function _setPod(IDecentralizedIndex _pod) internal {
        if (address(_pod) == address(0)) {
            return;
        }
        require(address(pod) == address(0), "S");
        pod = _pod;
        emit SetPod(address(_pod));
    }

    function setIndexUtils(IIndexUtils _utils) external onlyOwner {
        indexUtils = _utils;
        emit SetIndexUtils(address(_utils));
    }

    function setPodOracle(ISPTknOracle _oracle) external onlyOwner {
        podOracle = _oracle;
        emit SetPodOracle(address(_oracle));
    }

    function setLpSlippage(uint256 _slippage) external onlyOwner {
        require(_slippage <= 1000, "MAX");
        lpSlippage = _slippage;
        emit SetLpSlippage(_slippage);
    }

    function setYieldConvEnabled(bool _enabled, bool _triggerRewards, uint256 _lpMinOut, uint256 _deadline)
        external
        onlyOwner
    {
        require(yieldConvEnabled != _enabled, "T");
        if (_triggerRewards) _processRewardsToPodLp(_lpMinOut, _deadline);
        yieldConvEnabled = _enabled;
        emit SetYieldConvEnabled(_enabled);
    }

    function setProtocolFee(uint16 _newFee, uint256 _lpMinOut, uint256 _deadline) external onlyOwner {
        require(_newFee <= 1000, "MAX");
        _processRewardsToPodLp(_lpMinOut, _deadline);
        uint16 _oldFee = protocolFee;
        protocolFee = _newFee;
        emit SetProtocolFee(_oldFee, _newFee);
    }
}
