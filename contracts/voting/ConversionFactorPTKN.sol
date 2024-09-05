// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import '../interfaces/IDecentralizedIndex.sol';
import '../interfaces/IStakingConversionFactor.sol';

contract ConversionFactorPTKN is IStakingConversionFactor {
  function getConversionFactor(
    address _pod
  )
    external
    view
    virtual
    override
    returns (uint256 _factor, uint256 _denomenator)
  {
    (_factor, _denomenator) = _calculateCbrWithDen(_pod);
  }

  function _calculateCbrWithDen(
    address _pTKN
  ) internal view returns (uint256, uint256) {
    uint256 _den = 10 ** 18;
    IDecentralizedIndex.IndexAssetInfo[] memory _assets = IDecentralizedIndex(
      _pTKN
    ).getAllAssets();
    uint256 _firstAssetBal = IERC20(_assets[0].token).balanceOf(_pTKN);
    uint256 _totalSupply = IDecentralizedIndex(_pTKN).totalSupply();
    return (
      _totalSupply == 0
        ? _den
        : (_den * _firstAssetBal * 10 ** IERC20Metadata(_pTKN).decimals()) /
          _totalSupply /
          10 ** IERC20Metadata(_assets[0].token).decimals(),
      _den
    );
  }
}
