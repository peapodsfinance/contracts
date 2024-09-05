// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './interfaces/IDecentralizedIndex.sol';
import './interfaces/IDexAdapter.sol';
import './interfaces/IFlashLoanRecipient.sol';
import './interfaces/IProtocolFeeRouter.sol';
import './interfaces/IRewardsWhitelister.sol';
import './interfaces/ITokenRewards.sol';
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
  IProtocolFeeRouter constant PROTOCOL_FEE_ROUTER =
    IProtocolFeeRouter(0x7d544DD34ABbE24C8832db27820Ff53C151e949b);
  IRewardsWhitelister constant REWARDS_WHITELIST =
    IRewardsWhitelister(0xEc0Eb48d2D638f241c1a7F109e38ef2901E9450F);
  IV3TwapUtilities constant V3_TWAP_UTILS =
    IV3TwapUtilities(0x024ff47D552cB222b265D68C7aeB26E586D5229D);

  uint256 public immutable override FLASH_FEE_AMOUNT_DAI; // 10 DAI
  address public immutable override PAIRED_LP_TOKEN;
  IDexAdapter public immutable DEX_HANDLER;
  address immutable V2_ROUTER;
  address immutable V3_ROUTER;
  address immutable WETH;
  address V2_POOL;

  IndexType public immutable override indexType;
  uint256 public immutable override created;
  address public immutable override lpRewardsToken;
  address public override lpStakingPool;
  uint8 public override unlocked = 1;

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
  bool _initialized;

  event FlashLoan(
    address indexed executor,
    address indexed recipient,
    address token,
    uint256 amount
  );

  modifier lock() {
    require(unlocked == 1, 'L');
    unlocked = 0;
    _;
    unlocked = 1;
  }

  modifier onlyPartner() {
    require(_msgSender() == config.partner, 'P');
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
    address _dexHandler,
    bool _stakeRestriction
  ) ERC20(_name, _symbol) ERC20Permit(_name) {
    require(_fees.buy <= (uint256(DEN) * 20) / 100);
    require(_fees.sell <= (uint256(DEN) * 20) / 100);
    require(_fees.burn <= (uint256(DEN) * 70) / 100);
    require(_fees.bond <= (uint256(DEN) * 99) / 100);
    require(_fees.debond <= (uint256(DEN) * 99) / 100);
    require(_fees.partner <= (uint256(DEN) * 5) / 100);

    indexType = _idxType;
    created = block.timestamp;
    fees = _fees;
    config = _config;
    lpRewardsToken = _lpRewardsToken;
    DEX_HANDLER = IDexAdapter(_dexHandler);
    address _v2Router = DEX_HANDLER.V2_ROUTER();
    V2_ROUTER = _v2Router;
    V3_ROUTER = DEX_HANDLER.V3_ROUTER();
    address _finalPairedLpToken = _pairedLpToken == address(0)
      ? DAI
      : _pairedLpToken;
    PAIRED_LP_TOKEN = _finalPairedLpToken;
    FLASH_FEE_AMOUNT_DAI = 10 * 10 ** IERC20Metadata(DAI).decimals(); // 10 DAI
    lpStakingPool = address(
      new StakingPoolToken(
        string.concat('Staked ', _name),
        string.concat('s', _symbol),
        _finalPairedLpToken,
        lpRewardsToken,
        _stakeRestriction ? _msgSender() : address(0),
        PROTOCOL_FEE_ROUTER,
        REWARDS_WHITELIST,
        DEX_HANDLER,
        V3_TWAP_UTILS
      )
    );
    if (!DEX_HANDLER.ASYNC_INITIALIZE()) {
      _initialize();
    }
    WETH = IDexAdapter(_dexHandler).WETH();
    emit Create(address(this), _msgSender());
  }

  function initialize() external {
    _initialize();
  }

  /// @notice The ```_initialize``` function initialized a new LP pair for the pod + pairedLpAsset
  function _initialize() internal {
    require(!_initialized, 'O');
    _initialized = true;
    address _v2Pool = DEX_HANDLER.getV2Pool(address(this), PAIRED_LP_TOKEN);
    if (_v2Pool == address(0)) {
      _v2Pool = DEX_HANDLER.createV2Pool(address(this), PAIRED_LP_TOKEN);
    }
    StakingPoolToken(lpStakingPool).setStakingToken(_v2Pool);
    StakingPoolToken(lpStakingPool).renounceOwnership();
    V2_POOL = _v2Pool;
    emit Initialize(_msgSender(), _v2Pool);
  }

  /// @notice The ```_transfer``` function overrides the standard ERC20 _transfer to handle fee processing for a pod
  /// @param _from Where pTKN are being transferred from
  /// @param _to Where pTKN are being transferred to
  /// @param _amount Amount of pTKN being transferred
  function _transfer(
    address _from,
    address _to,
    uint256 _amount
  ) internal virtual override {
    require(!_blacklist[_to], 'BK');
    bool _buy = _from == V2_POOL && _to != V2_ROUTER;
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
      if (!_buy && !_sell && config.hasTransferTax) {
        _fee = _amount / 10000; // 0.01%
        _fee = _fee == 0 && _amount > 0 ? 1 : _fee;
        super._transfer(_from, address(this), _fee);
      }
    }
    _processBurnFee(_fee);
    super._transfer(_from, _to, _amount - _fee);
  }

  /// @notice The ```_processPreSwapFeesAndSwap``` function processes fees that could be pending for a pod
  function _processPreSwapFeesAndSwap() internal {
    bool _passesSwapDelay = block.timestamp > _lastSwap + SWAP_DELAY;
    if (!_passesSwapDelay) {
      return;
    }
    uint256 _bal = balanceOf(address(this));
    if (_bal == 0) {
      return;
    }
    uint256 _lpBal = balanceOf(V2_POOL);
    uint256 _min = block.chainid == 1 ? _lpBal / 1000 : _lpBal / 4000; // 0.1%/0.025% LP bal
    uint256 _max = _lpBal / 100; // 1%
    if (_bal >= _min && _lpBal > 0) {
      _swapping = 1;
      _lastSwap = uint64(block.timestamp);
      uint256 _totalAmt = _bal > _max ? _max : _bal;
      uint256 _partnerAmt;
      if (
        fees.partner > 0 &&
        config.partner != address(0) &&
        !_blacklist[config.partner]
      ) {
        _partnerAmt = (_totalAmt * fees.partner) / DEN;
        super._transfer(address(this), config.partner, _partnerAmt);
      }
      _feeSwap(_totalAmt - _partnerAmt);
      _swapping = 0;
    }
  }

  /// @notice The ```_processBurnFee``` function burns pTKN based on the burn fee, which turns the pod
  /// @notice into a vault where holders have more underlying TKN to pTKN as burn fees process over time
  /// @param _amtToProcess Number of pTKN being burned
  function _processBurnFee(uint256 _amtToProcess) internal {
    if (_amtToProcess == 0 || fees.burn == 0) {
      return;
    }
    _burn(address(this), (_amtToProcess * fees.burn) / DEN);
  }

  /// @notice The ```_feeSwap``` function processes built up fees by converting to pairedLpToken
  /// @param _amount Number of pTKN being processed for yield
  function _feeSwap(uint256 _amount) internal {
    _approve(address(this), address(DEX_HANDLER), _amount);
    address _rewards = StakingPoolToken(lpStakingPool).POOL_REWARDS();
    uint256 _pairedLpBalBefore = IERC20(PAIRED_LP_TOKEN).balanceOf(_rewards);
    DEX_HANDLER.swapV2Single(
      address(this),
      PAIRED_LP_TOKEN,
      _amount,
      0,
      _rewards
    );

    if (PAIRED_LP_TOKEN == lpRewardsToken) {
      uint256 _newPairedLpTkns = IERC20(PAIRED_LP_TOKEN).balanceOf(_rewards) -
        _pairedLpBalBefore;
      if (_newPairedLpTkns > 0) {
        ITokenRewards(_rewards).depositRewardsNoTransfer(
          PAIRED_LP_TOKEN,
          _newPairedLpTkns
        );
      }
    } else if (IERC20(PAIRED_LP_TOKEN).balanceOf(_rewards) > 0) {
      ITokenRewards(_rewards).depositFromPairedLpToken(0);
    }
  }

  /// @notice The ```_transferFromAndValidate``` function is basically the _transfer with hardcoded _to to this CA and executes
  /// @notice a token transfer with balance validation to revert if balances aren't updated as expected
  /// @notice on transfer (i.e. transfer fees, etc.)
  /// @param _token The token we're transferring
  /// @param _sender The token we're transferring
  /// @param _amount Number of tokens to transfer
  function _transferFromAndValidate(
    IERC20 _token,
    address _sender,
    uint256 _amount
  ) internal {
    uint256 _balanceBefore = _token.balanceOf(address(this));
    _token.safeTransferFrom(_sender, address(this), _amount);
    require(_token.balanceOf(address(this)) >= _balanceBefore + _amount, 'TV');
  }

  /// @notice The ```_bond``` function should be called from external bond() to handle validation and partner logic
  function _bond() internal {
    require(_initialized, 'I');
    if (_partnerFirstWrapped == 0 && _msgSender() == config.partner) {
      _partnerFirstWrapped = uint64(block.timestamp);
    }
  }

  /// @notice The ```_canWrapFeeFree``` function checks if the wrapping user can wrap without fees
  /// @param _wrapper The user wrapping into the pod
  /// @return bool Whether the user can wrap fee free
  function _canWrapFeeFree(address _wrapper) internal view returns (bool) {
    return
      _isFirstIn() ||
      (_wrapper == config.partner &&
        _partnerFirstWrapped == 0 &&
        block.timestamp <= created + 7 days);
  }

  /// @notice The ```_isFirstIn``` function confirms if the user is the first to wrap
  /// @return bool Whether the user is the first one in
  function _isFirstIn() internal view returns (bool) {
    return totalSupply() == 0;
  }

  /// @notice The ```_isLastOut``` function checks if the user is the last one out
  /// @param _debondAmount Number of pTKN being unwrapped
  /// @return bool Whether the user is the last one out
  function _isLastOut(uint256 _debondAmount) internal view returns (bool) {
    return _debondAmount >= (totalSupply() * 98) / 100;
  }

  /// @notice The ```processPreSwapFeesAndSwap``` function allows the rewards CA for the pod to process fees as needed
  function processPreSwapFeesAndSwap() external override {
    require(
      _msgSender() == StakingPoolToken(lpStakingPool).POOL_REWARDS(),
      'R'
    );
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

  /// @notice The ```burn``` function allows any user to burn an amount of their pTKN
  /// @param _amount Number of pTKN to burn
  function burn(uint256 _amount) external lock {
    _burn(_msgSender(), _amount);
  }

  /// @notice The ```addLiquidityV2``` function mints new liquidity for the pod
  /// @param _idxLPTokens Number pTKN to add to liquidity
  /// @param _pairedLPTokens Number of pairedLpToken to add to liquidity
  /// @param _slippage LP slippage with 1000 precision
  /// @param _deadline LP validation deadline
  /// @return _liquidity Number of new liquidity tokens minted
  function addLiquidityV2(
    uint256 _idxLPTokens,
    uint256 _pairedLPTokens,
    uint256 _slippage, // 100 == 10%, 1000 == 100%
    uint256 _deadline
  ) external override lock noSwapOrFee returns (uint256) {
    uint256 _idxTokensBefore = balanceOf(address(this));
    uint256 _pairedBefore = IERC20(PAIRED_LP_TOKEN).balanceOf(address(this));

    super._transfer(_msgSender(), address(this), _idxLPTokens);
    _approve(address(this), address(DEX_HANDLER), _idxLPTokens);

    IERC20(PAIRED_LP_TOKEN).safeTransferFrom(
      _msgSender(),
      address(this),
      _pairedLPTokens
    );
    IERC20(PAIRED_LP_TOKEN).safeIncreaseAllowance(
      address(DEX_HANDLER),
      _pairedLPTokens
    );

    uint256 _poolBalBefore = IERC20(
      DEX_HANDLER.getV2Pool(address(this), PAIRED_LP_TOKEN)
    ).balanceOf(_msgSender());
    DEX_HANDLER.addLiquidity(
      address(this),
      PAIRED_LP_TOKEN,
      _idxLPTokens,
      _pairedLPTokens,
      (_idxLPTokens * (1000 - _slippage)) / 1000,
      (_pairedLPTokens * (1000 - _slippage)) / 1000,
      _msgSender(),
      _deadline
    );
    IERC20(PAIRED_LP_TOKEN).safeApprove(address(DEX_HANDLER), 0);

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
    return
      IERC20(DEX_HANDLER.getV2Pool(address(this), PAIRED_LP_TOKEN)).balanceOf(
        _msgSender()
      ) - _poolBalBefore;
  }

  /// @notice The ```removeLiquidityV2``` function burns pod liquidity
  /// @param _lpTokens Number of liquidity tokens to burn/remove
  /// @param _minIdxTokens Number of pTKN to receive at a minimum, slippage
  /// @param _minPairedLpToken Number of pairedLpToken to receive at a minimum, slippage
  /// @param _deadline LP validation deadline
  function removeLiquidityV2(
    uint256 _lpTokens,
    uint256 _minIdxTokens, // 0 == 100% slippage
    uint256 _minPairedLpToken, // 0 == 100% slippage
    uint256 _deadline
  ) external override lock noSwapOrFee {
    _lpTokens = _lpTokens == 0
      ? IERC20(V2_POOL).balanceOf(_msgSender())
      : _lpTokens;
    require(_lpTokens > 0, 'LT');

    IERC20(V2_POOL).safeTransferFrom(_msgSender(), address(this), _lpTokens);
    IERC20(V2_POOL).safeIncreaseAllowance(address(DEX_HANDLER), _lpTokens);
    DEX_HANDLER.removeLiquidity(
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

  /// @notice The ```flash``` function allows to flash loan underlying TKN from the pod
  /// @param _recipient User to receive underlying TKN for the flash loan
  /// @param _token TKN to borrow
  /// @param _amount Number of underying TKN to borrow
  /// @param _data Any data the recipient wants to be passed on the flash loan callback callback
  function flash(
    address _recipient,
    address _token,
    uint256 _amount,
    bytes calldata _data
  ) external override lock {
    require(_isTokenInIndex[_token], 'X');
    address _rewards = StakingPoolToken(lpStakingPool).POOL_REWARDS();
    address _feeRecipient = lpRewardsToken == DAI
      ? address(this)
      : PAIRED_LP_TOKEN == DAI
        ? _rewards
        : Ownable(address(V3_TWAP_UTILS)).owner();
    IERC20(DAI).safeTransferFrom(
      _msgSender(),
      _feeRecipient,
      FLASH_FEE_AMOUNT_DAI
    );
    if (lpRewardsToken == DAI) {
      IERC20(DAI).safeIncreaseAllowance(_rewards, FLASH_FEE_AMOUNT_DAI);
      ITokenRewards(_rewards).depositRewards(DAI, FLASH_FEE_AMOUNT_DAI);
    }
    uint256 _balance = IERC20(_token).balanceOf(address(this));
    IERC20(_token).safeTransfer(_recipient, _amount);
    IFlashLoanRecipient(_recipient).callback(_data);
    require(IERC20(_token).balanceOf(address(this)) >= _balance, 'FA');
    emit FlashLoan(_msgSender(), _recipient, _token, _amount);
  }

  function setPartner(address _partner) external onlyPartner {
    config.partner = _partner;
    emit SetPartner(_msgSender(), _partner);
  }

  function setPartnerFee(uint16 _fee) external onlyPartner {
    require(_fee < fees.partner, 'L');
    fees.partner = _fee;
    emit SetPartnerFee(_msgSender(), _fee);
  }

  function rescueERC20(address _token) external lock {
    // cannot withdraw tokens/assets that belong to the index
    require(!isAsset(_token) && _token != address(this), 'U');
    IERC20(_token).safeTransfer(
      Ownable(address(V3_TWAP_UTILS)).owner(),
      IERC20(_token).balanceOf(address(this))
    );
  }

  function rescueETH() external lock {
    require(address(this).balance > 0, 'E');
    (bool _sent, ) = Ownable(address(V3_TWAP_UTILS)).owner().call{
      value: address(this).balance
    }('');
    require(_sent, 'S');
  }

  receive() external payable {}
}
