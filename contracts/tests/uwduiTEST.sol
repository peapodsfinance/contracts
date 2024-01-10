// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '../UnweightedIndex.sol';

contract uwduiTEST is UnweightedIndex {
  constructor(
    address[] memory _pools,
    address _rewardsToken,
    address _v2Router,
    address _v3USDCWETHPool,
    Fees memory _fees
  )
    UnweightedIndex(
      'zUnweighted Blue Chip Idx',
      'uwzTESTTTBC',
      _fees,
      _pools,
      address(0),
      address(0),
      _rewardsToken,
      _v2Router,
      _v3USDCWETHPool,
      false
    )
  {}
}
