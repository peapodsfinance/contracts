// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import { PodHandler } from '../handlers/PodHandler.sol';
import { LeverageManagerHandler } from '../handlers/LeverageManagerHandler.sol';
import { AutoCompoundingPodLpHandler } from '../handlers/AutoCompoundingPodLpHandler.sol';
import { StakingPoolHandler } from '../handlers/StakingPoolHandler.sol';
import { LendingAssetVaultHandler } from '../handlers/LendingAssetVaultHandler.sol';

contract ForgeTest is
  PodHandler,
  LeverageManagerHandler,
  AutoCompoundingPodLpHandler,
  StakingPoolHandler,
  LendingAssetVaultHandler
{
  function setUp() public {
    setup();
  }

  function test_dev() public {
    pod_bond(58674322, 132456758, 675342, 10e6);
  }

  function test_replay() public {
    try
      this.pod_bond(
        288567818787326643023506815421089704617048639194509319202485712218260114617,
        29515901080938621889877141707036352226864468261646330083102350409534879807,
        3870987322940035436806899355602515513976214643090434126647769765086004233,
        3751223273476981504383446139001619864832943303305560785665809932553786858138
      )
    {} catch {}

    try
      this.leverageManager_initializePosition(
        2,
        864785375698752058026248862771397146954785887553859643720868042307
      )
    {} catch {}

    try
      this.leverageManager_initializePosition(
        1819375668301367448498623959745513526506284565287366183654757440,
        3
      )
    {} catch {}

    try
      this.pod_bond(
        1058043035031271676877037547360272025750726995625444698139083556944597505,
        37099228305815352059887914428010197444677666189399271658359950942529764283,
        3,
        195142413648582603965278722008899869974060046834873831284646952907412388109
      )
    {} catch {}

    try
      this.leverageManager_addLeverage(
        452,
        195855133400655695634839316703620474931054898400273827754150347191765,
        1306268131036379882820999612676404294589193942984015250594
      )
    {} catch {}

    try
      this.lendingAssetVault_mint(
        0,
        2634170383473269478657045188223238445090854823,
        313986741269926707370551517818097301939177071860
      )
    {} catch {}

    try
      this.leverageManager_addLeverage(
        1,
        1294187552646389794390633050136096068607040314971578608717635250460852493,
        0
      )
    {} catch {}

    vm.warp(block.timestamp + 300);
    vm.roll(block.number + 8424);
    try this.targetSenders() {} catch {}

    try
      this.lendingAssetVault_mint(
        1524785992,
        108776317867757498538207833169729791335201215042346861551372842237787801740791,
        47820720636002330276591034207980768011018379773415868347601725519876016888918
      )
    {} catch {}

    vm.warp(block.timestamp + 4);
    vm.roll(block.number + 504);
    try
      this.leverageManager_removeLeverage(
        2169160151835457429239563968277087476754221861494072700072873222538680,
        121897565111050848480420525242122669465525576558080507554599311911979376,
        1001
      )
    {} catch {}

    lendingAssetVault_redeemFromVault(
      2049310266298554106128788846739428712196230724200586343442608393014111646599,
      4369999,
      115792089237316195423570985008687907853269984665640564039457584007913129639935
    );
  }
}
