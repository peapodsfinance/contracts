// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import './interfaces/IDecentralizedIndex.sol';
import './interfaces/IStakingPoolToken.sol';
import './Zapper.sol';

interface IIndexUtilsOld {
  function unstakeAndRemoveLP(
    IDecentralizedIndex _indexFund,
    uint256 _amountStakedTokens,
    uint256 _minLPTokens,
    uint256 _minDAI
  ) external;
}

interface IIndexUtilsNew is IIndexUtilsOld {
  function addLPAndStake(
    IDecentralizedIndex _indexFund,
    uint256 _amountIdxTokens,
    address _pairedLpTokenProvided,
    uint256 _amountPairedLpToken,
    uint256 _slippage,
    uint256 _deadline
  ) external;
}

contract LegacyPodMigration is Ownable, Zapper {
  using SafeERC20 for IERC20;

  uint256 _minMintOutSlip = 200;

  address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  address constant legacyIdxUtils = 0x88B6dB67000F8Ef34AE1a34542B2E4b43B87d9b7;
  address constant newIdxUtils = 0x9A103aB4FE2De5db16338B16FD7550D21d7b8DB6;
  address constant ppPP = 0x515e7fd1C29263DFF8d987f15FA00c12cd10A49b;
  address constant pPEAS = 0x027CE48B9b346728557e8D420Fe936A72BF9b1C7;

  address public immutable PEAS;
  address public immutable sppPP;
  address public immutable spPEAS;

  constructor(
    address _v2Router,
    IV3TwapUtilities _v3TwapUtilities
  ) Zapper(_v2Router, _v3TwapUtilities) {
    IDecentralizedIndex.IndexAssetInfo[] memory _assets = IDecentralizedIndex(
      ppPP
    ).getAllAssets();
    PEAS = _assets[0].token;
    sppPP = IDecentralizedIndex(ppPP).lpStakingPool();
    spPEAS = IDecentralizedIndex(pPEAS).lpStakingPool();
  }

  function migratePP(uint256 _amount) external {
    IERC20(ppPP).safeTransferFrom(_msgSender(), address(this), _amount);
    uint256 _newpPEASBal = _migrateppPPTopPEAS(_amount);
    IERC20(pPEAS).safeTransfer(_msgSender(), _newpPEASBal);
  }

  function migrateSPP(
    uint256 _amount,
    uint256 _minLPTokens,
    uint256 _minDAI
  ) external {
    IERC20(sppPP).safeTransferFrom(_msgSender(), address(this), _amount);
    uint256 _ppBalBefore = IERC20(ppPP).balanceOf(address(this));
    uint256 _daiBalBefore = IERC20(DAI).balanceOf(address(this));
    uint256 _pohmBalBefore = IERC20(pOHM).balanceOf(address(this));
    uint256 _ppeasBalBefore = IERC20(pPEAS).balanceOf(address(this));
    IERC20(sppPP).safeIncreaseAllowance(legacyIdxUtils, _amount);
    IIndexUtilsOld(legacyIdxUtils).unstakeAndRemoveLP(
      IDecentralizedIndex(ppPP),
      _amount,
      _minLPTokens,
      _minDAI
    );
    address _WETH = IUniswapV2Router02(V2_ROUTER).WETH();
    uint256 _ppBal = IERC20(ppPP).balanceOf(address(this)) - _ppBalBefore;
    uint256 _daiBal = IERC20(DAI).balanceOf(address(this)) - _daiBalBefore;
    uint256 _amountWETH = _zap(DAI, _WETH, _daiBal, 0);
    uint256 _amountOHM = _zap(_WETH, OHM, _amountWETH, 0);
    IERC20(OHM).safeIncreaseAllowance(pOHM, _amountOHM);
    IDecentralizedIndex(pOHM).bond(OHM, _amountOHM, 0);
    uint256 _newPohmBal = IERC20(pOHM).balanceOf(address(this)) -
      _pohmBalBefore;
    uint256 _newpPEASBal = _migrateppPPTopPEAS(_ppBal);

    IERC20(pPEAS).safeIncreaseAllowance(newIdxUtils, _newpPEASBal);
    IERC20(DAI).safeIncreaseAllowance(newIdxUtils, _newPohmBal);
    uint256 _newLpBalBefore = IERC20(spPEAS).balanceOf(address(this));
    IIndexUtilsNew(newIdxUtils).addLPAndStake(
      IDecentralizedIndex(pPEAS),
      _newpPEASBal,
      pOHM,
      _newPohmBal,
      _slippage,
      block.timestamp
    );
    IERC20(spPEAS).safeTransfer(
      _msgSender(),
      IERC20(spPEAS).balanceOf(address(this)) - _newLpBalBefore
    );
    _checkAndRefundERC20(_msgSender(), pPEAS, _ppeasBalBefore);
    _checkAndRefundERC20(_msgSender(), pOHM, _pohmBalBefore);
    _checkAndRefundERC20(_msgSender(), DAI, _daiBalBefore);
  }

  function _checkAndRefundERC20(
    address _user,
    address _asset,
    uint256 _beforeBal
  ) internal {
    uint256 _curBal = IERC20(_asset).balanceOf(address(this));
    if (_curBal > _beforeBal) {
      IERC20(_asset).safeTransfer(_user, _curBal - _beforeBal);
    }
  }

  function _migrateppPPTopPEAS(uint256 _amountPP) internal returns (uint256) {
    uint256 _peasBal = IERC20(PEAS).balanceOf(address(this));
    address[] memory _noop1 = new address[](0);
    uint8[] memory _noop2 = new uint8[](0);
    IDecentralizedIndex(ppPP).debond(_amountPP, _noop1, _noop2);
    uint256 _newPeas = IERC20(PEAS).balanceOf(address(this)) - _peasBal;
    IERC20(PEAS).safeIncreaseAllowance(pPEAS, _newPeas);
    uint256 _pPEASBal = IERC20(pPEAS).balanceOf(address(this));
    IDecentralizedIndex(pPEAS).bond(
      PEAS,
      _newPeas,
      (_amountPP * (1000 - _minMintOutSlip)) / 1000
    );
    return IERC20(pPEAS).balanceOf(address(this)) - _pPEASBal;
  }

  function setMinMintOutSlip(uint256 _minOutSlip) external onlyOwner {
    _minMintOutSlip = _minOutSlip;
  }
}
