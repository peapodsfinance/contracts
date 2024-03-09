// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@uniswap/v3-periphery/contracts/interfaces/IPeripheryImmutableState.sol';
import './interfaces/ICamelotRouter.sol';
import './interfaces/IDecentralizedIndex.sol';
import './interfaces/IFlashLoanRecipient.sol';
import './interfaces/IProtocolFeeRouter.sol';
import './interfaces/ITokenRewards.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Router02.sol';
import './StakingPoolToken.sol';

abstract contract DecentralizedIndex is
  IDecentralizedIndex,
  ERC20,
  ERC20Permit
{
  using SafeERC20 for IERC20;

  uint16 constant DEN = 10000;
  uint8 constant SWAP_DELAY = 20; // seconds
  address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  address constant V3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
  IProtocolFeeRouter constant PROTOCOL_FEE_ROUTER =
    IProtocolFeeRouter(0x7d544DD34ABbE24C8832db27820Ff53C151e949b);
  IV3TwapUtilities constant V3_TWAP_UTILS =
    IV3TwapUtilities(0x024ff47D552cB222b265D68C7aeB26E586D5229D);

  uint64 public constant override FLASH_FEE = 10; // 10 DAI
  address public immutable override PAIRED_LP_TOKEN;
  address immutable V2_ROUTER;
  address immutable V2_POOL;
  address immutable WETH;

  IndexType public immutable override indexType;
  uint256 public immutable override created;
  address public immutable override lpStakingPool;
  address public immutable override lpRewardsToken;

  Config public config;
  Fees public fees;
  IndexAssetInfo[] public indexTokens;
  mapping(address => bool) _isTokenInIndex;
  mapping(address => uint8) _fundTokenIdx;
  mapping(address => bool) _blacklist;

  uint64 _partnerFirstWrapped;

  uint64 _lastSwap;
  uint8 _swapping;
  uint8 _swapAndFeeOn = 1;
  uint8 _unlocked = 1;

  event FlashLoan(
    address indexed executor,
    address indexed recipient,
    address token,
    uint256 amount
  );

  modifier lock() {
    require(_unlocked == 1, 'LOCKED');
    _unlocked = 0;
    _;
    _unlocked = 1;
  }

  modifier onlyPartner() {
    require(_msgSender() == config.partner, 'PARTNER');
    _;
  }

  modifier onlyRewards() {
    require(
      _msgSender() == StakingPoolToken(lpStakingPool).poolRewards(),
      'REWARDS'
    );
    _;
  }

  modifier noSwapOrFee() {
    _swapAndFeeOn = 0;
    _;
    _swapAndFeeOn = 1;
  }

  constructor(
    string memory _name,
    string memory _symbol,
    IndexType _idxType,
    Config memory _config,
    Fees memory _fees,
    address _pairedLpToken,
    address _lpRewardsToken,
    address _v2Router,
    bool _stakeRestriction
  ) ERC20(_name, _symbol) ERC20Permit(_name) {
    require(_fees.buy <= (DEN * 20) / 100, 'lte20%');
    require(_fees.sell <= (DEN * 20) / 100, 'lte20%');
    require(_fees.burn <= (DEN * 70) / 100, 'lte70%');
    require(_fees.bond <= (DEN * 99) / 100, 'lt99%');
    require(_fees.debond <= (DEN * 99) / 100, 'lt99%');
    require(_fees.partner <= (DEN * 5) / 100, 'lte5%');

    indexType = _idxType;
    created = block.timestamp;
    fees = _fees;
    config = _config;
    lpRewardsToken = _lpRewardsToken;
    V2_ROUTER = _v2Router;
    address _finalPairedLpToken = _pairedLpToken == address(0)
      ? DAI
      : _pairedLpToken;
    PAIRED_LP_TOKEN = _finalPairedLpToken;
    address _v2Pool = IUniswapV2Factory(IUniswapV2Router02(_v2Router).factory())
      .createPair(address(this), _finalPairedLpToken);
    lpStakingPool = address(
      new StakingPoolToken(
        string(abi.encodePacked('Staked ', _name)),
        string(abi.encodePacked('s', _symbol)),
        _finalPairedLpToken,
        _v2Pool,
        _lpRewardsToken,
        _stakeRestriction ? _msgSender() : address(0),
        V3_ROUTER,
        PROTOCOL_FEE_ROUTER,
        V3_TWAP_UTILS
      )
    );
    V2_POOL = _v2Pool;
    WETH = IUniswapV2Router02(_v2Router).WETH();
    emit Create(address(this), _msgSender());
  }

  function _transfer(
    address _from,
    address _to,
    uint256 _amount
  ) internal virtual override {
    require(!_blacklist[_to], 'BLKLST');
    bool _buy = _from == V2_POOL && _to != address(V2_ROUTER);
    bool _sell = _to == V2_POOL;
    uint256 _fee;
    if (_swapping == 0 && _swapAndFeeOn == 1) {
      if (_from != V2_POOL) {
        _processPreSwapFeesAndSwap();
      }
      if (_buy && fees.buy > 0) {
        _fee = (_amount * fees.buy) / DEN;
        super._transfer(_from, address(this), _fee);
      }
      if (_sell && fees.sell > 0) {
        _fee = (_amount * fees.sell) / DEN;
        super._transfer(_from, address(this), _fee);
      }
      if (config.hasTransferTax && !_buy && !_sell) {
        _fee = _amount / 10000; // 0.01%
        _fee = _fee == 0 ? 1 : _fee;
        super._transfer(_from, address(this), _fee);
      }
    }
    _processBurnFee(_fee);
    super._transfer(_from, _to, _amount - _fee);
  }

  function _processPreSwapFeesAndSwap() internal {
    bool _passesSwapDelay = block.timestamp > _lastSwap + SWAP_DELAY;
    uint256 _bal = balanceOf(address(this));
    if (_bal == 0) {
      return;
    }
    uint256 _lpBal = balanceOf(V2_POOL);
    uint256 _min = (_lpBal * 25) / 100000; // 0.025% LP bal
    uint256 _max = _lpBal / 100; // 1%
    if (_passesSwapDelay && _bal >= _min && _lpBal > 0) {
      _swapping = 1;
      _lastSwap = uint64(block.timestamp);
      uint256 _totalAmt = _bal > _max ? _max : _bal;
      uint256 _partnerAmt;
      if (fees.partner > 0 && config.partner != address(0)) {
        _partnerAmt = (_totalAmt * fees.partner) / DEN;
        super._transfer(address(this), config.partner, _partnerAmt);
      }
      _feeSwap(_totalAmt - _partnerAmt);
      _swapping = 0;
    }
  }

  function _processBurnFee(uint256 _amtToProcess) internal {
    if (_amtToProcess == 0 || fees.burn == 0) {
      return;
    }
    _burn(address(this), (_amtToProcess * fees.burn) / DEN);
  }

  function _feeSwap(uint256 _amount) internal {
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = PAIRED_LP_TOKEN;
    _approve(address(this), V2_ROUTER, _amount);
    address _rewards = StakingPoolToken(lpStakingPool).poolRewards();
    uint256 _pairedLpBalBefore = IERC20(PAIRED_LP_TOKEN).balanceOf(
      address(this)
    );
    address _recipient = PAIRED_LP_TOKEN == lpRewardsToken
      ? address(this)
      : _rewards;
    if (block.chainid == 42161) {
      ICamelotRouter(V2_ROUTER)
        .swapExactTokensForTokensSupportingFeeOnTransferTokens(
          _amount,
          0,
          path,
          _recipient,
          Ownable(address(V3_TWAP_UTILS)).owner(),
          block.timestamp
        );
    } else {
      IUniswapV2Router02(V2_ROUTER)
        .swapExactTokensForTokensSupportingFeeOnTransferTokens(
          _amount,
          0,
          path,
          _recipient,
          block.timestamp
        );
    }
    if (PAIRED_LP_TOKEN == lpRewardsToken) {
      uint256 _newPairedLpTkns = IERC20(PAIRED_LP_TOKEN).balanceOf(
        address(this)
      ) - _pairedLpBalBefore;
      if (_newPairedLpTkns > 0) {
        IERC20(PAIRED_LP_TOKEN).safeIncreaseAllowance(
          _rewards,
          _newPairedLpTkns
        );
        ITokenRewards(_rewards).depositRewards(_newPairedLpTkns);
      }
    } else if (IERC20(PAIRED_LP_TOKEN).balanceOf(_rewards) > 0) {
      ITokenRewards(_rewards).depositFromPairedLpToken(0, 0);
    }
  }

  function _transferFromAndValidate(
    IERC20 _token,
    address _sender,
    uint256 _amount
  ) internal {
    uint256 _balanceBefore = _token.balanceOf(address(this));
    _token.safeTransferFrom(_sender, address(this), _amount);
    require(
      _token.balanceOf(address(this)) >= _balanceBefore + _amount,
      'TFRVAL'
    );
  }

  function _bond() internal {
    if (_partnerFirstWrapped == 0 && _msgSender() == config.partner) {
      _partnerFirstWrapped = uint64(block.timestamp);
    }
  }

  function _canWrapFeeFree(address _wrapper) internal view returns (bool) {
    return
      _isFirstIn() ||
      (_wrapper == config.partner &&
        _partnerFirstWrapped == 0 &&
        block.timestamp <= created + 7 days);
  }

  function _isFirstIn() internal view returns (bool) {
    return totalSupply() == 0;
  }

  function _isLastOut(uint256 _debondAmount) internal view returns (bool) {
    return _debondAmount >= (totalSupply() * 98) / 100;
  }

  function processPreSwapFeesAndSwap() external override onlyRewards {
    _processPreSwapFeesAndSwap();
  }

  function partner() external view override returns (address) {
    return config.partner;
  }

  function BOND_FEE() external view override returns (uint16) {
    return fees.bond;
  }

  function DEBOND_FEE() external view override returns (uint16) {
    return fees.debond;
  }

  function isAsset(address _token) public view override returns (bool) {
    return _isTokenInIndex[_token];
  }

  function getAllAssets()
    external
    view
    override
    returns (IndexAssetInfo[] memory)
  {
    return indexTokens;
  }

  function burn(uint256 _amount) external lock {
    _burn(_msgSender(), _amount);
  }

  function manualProcessFee(uint256 _slip) external {
    _transfer(address(this), address(this), 0);
    address _rewards = StakingPoolToken(lpStakingPool).poolRewards();
    ITokenRewards(_rewards).depositFromPairedLpToken(
      0,
      _slip > 50 ? 50 : _slip // 5% max
    );
  }

  function addLiquidityV2(
    uint256 _idxLPTokens,
    uint256 _pairedLPTokens,
    uint256 _slippage, // 100 == 10%, 1000 == 100%
    uint256 _deadline
  ) external override lock noSwapOrFee {
    uint256 _idxTokensBefore = balanceOf(address(this));
    uint256 _pairedBefore = IERC20(PAIRED_LP_TOKEN).balanceOf(address(this));

    super._transfer(_msgSender(), address(this), _idxLPTokens);
    _approve(address(this), V2_ROUTER, _idxLPTokens);

    IERC20(PAIRED_LP_TOKEN).safeTransferFrom(
      _msgSender(),
      address(this),
      _pairedLPTokens
    );
    IERC20(PAIRED_LP_TOKEN).safeIncreaseAllowance(V2_ROUTER, _pairedLPTokens);

    IUniswapV2Router02(V2_ROUTER).addLiquidity(
      address(this),
      PAIRED_LP_TOKEN,
      _idxLPTokens,
      _pairedLPTokens,
      (_idxLPTokens * (1000 - _slippage)) / 1000,
      (_pairedLPTokens * (1000 - _slippage)) / 1000,
      _msgSender(),
      _deadline
    );
    uint256 _remainingAllowance = IERC20(PAIRED_LP_TOKEN).allowance(
      address(this),
      V2_ROUTER
    );
    if (_remainingAllowance > 0) {
      IERC20(PAIRED_LP_TOKEN).safeDecreaseAllowance(
        V2_ROUTER,
        _remainingAllowance
      );
    }

    // check & refund excess tokens from LPing
    if (balanceOf(address(this)) > _idxTokensBefore) {
      super._transfer(
        address(this),
        _msgSender(),
        balanceOf(address(this)) - _idxTokensBefore
      );
    }
    if (IERC20(PAIRED_LP_TOKEN).balanceOf(address(this)) > _pairedBefore) {
      IERC20(PAIRED_LP_TOKEN).safeTransfer(
        _msgSender(),
        IERC20(PAIRED_LP_TOKEN).balanceOf(address(this)) - _pairedBefore
      );
    }
    emit AddLiquidity(_msgSender(), _idxLPTokens, _pairedLPTokens);
  }

  function removeLiquidityV2(
    uint256 _lpTokens,
    uint256 _minIdxTokens, // 0 == 100% slippage
    uint256 _minPairedLpToken, // 0 == 100% slippage
    uint256 _deadline
  ) external override lock noSwapOrFee {
    _lpTokens = _lpTokens == 0
      ? IERC20(V2_POOL).balanceOf(_msgSender())
      : _lpTokens;
    require(_lpTokens > 0, 'LPREM');

    IERC20(V2_POOL).safeTransferFrom(_msgSender(), address(this), _lpTokens);
    IERC20(V2_POOL).safeIncreaseAllowance(V2_ROUTER, _lpTokens);
    IUniswapV2Router02(V2_ROUTER).removeLiquidity(
      address(this),
      PAIRED_LP_TOKEN,
      _lpTokens,
      _minIdxTokens,
      _minPairedLpToken,
      _msgSender(),
      _deadline
    );
    emit RemoveLiquidity(_msgSender(), _lpTokens);
  }

  function flash(
    address _recipient,
    address _token,
    uint256 _amount,
    bytes calldata _data
  ) external override lock {
    require(_isTokenInIndex[_token], 'ONLYPODTKN');
    uint256 _amountDAI = FLASH_FEE * 10 ** IERC20Metadata(DAI).decimals();
    address _rewards = StakingPoolToken(lpStakingPool).poolRewards();
    address _feeRecipient = lpRewardsToken == DAI
      ? address(this)
      : PAIRED_LP_TOKEN == DAI
      ? _rewards
      : Ownable(address(V3_TWAP_UTILS)).owner();
    IERC20(DAI).safeTransferFrom(_msgSender(), _feeRecipient, _amountDAI);
    if (lpRewardsToken == DAI) {
      IERC20(DAI).safeIncreaseAllowance(_rewards, _amountDAI);
      ITokenRewards(_rewards).depositRewards(_amountDAI);
    }
    uint256 _balance = IERC20(_token).balanceOf(address(this));
    IERC20(_token).safeTransfer(_recipient, _amount);
    IFlashLoanRecipient(_recipient).callback(_data);
    require(IERC20(_token).balanceOf(address(this)) >= _balance, 'FLASHAFTER');
    emit FlashLoan(_msgSender(), _recipient, _token, _amount);
  }

  function setPartner(address _partner) external onlyPartner {
    config.partner = _partner;
  }

  function setPartnerFee(uint16 _fee) external onlyPartner {
    require(_fee < fees.partner, 'LTCUR');
    fees.partner = _fee;
  }

  function rescueERC20(address _token) external lock {
    // cannot withdraw tokens/assets that belong to the index
    require(!isAsset(_token) && _token != address(this), 'UNAVAILABLE');
    IERC20(_token).safeTransfer(
      Ownable(address(V3_TWAP_UTILS)).owner(),
      IERC20(_token).balanceOf(address(this))
    );
  }

  function rescueETH() external lock {
    require(address(this).balance > 0, 'NOETH');
    (bool _sent, ) = Ownable(address(V3_TWAP_UTILS)).owner().call{
      value: address(this).balance
    }('');
    require(_sent, 'SENT');
  }
}
