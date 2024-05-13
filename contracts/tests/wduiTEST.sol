// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '../WeightedIndex.sol';

contract wduiTEST is WeightedIndex {
  constructor(
    address[] memory _tokens,
    uint256[] memory _weights,
    address _rewardsToken,
    address _dexHandler,
    Config memory _config,
    Fees memory _fees
  )
    WeightedIndex(
      'zWeighted Blue Chip Idx',
      'wzTESTTTBC',
      _config,
      _fees,
      _tokens,
      _weights,
      address(0),
      _rewardsToken,
      _dexHandler,
      false
    )
  {}
}
