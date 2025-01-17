// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interfaces/IDecentralizedIndex.sol";
import "../interfaces/IStakingConversionFactor.sol";

contract ConversionFactorPTKN is IStakingConversionFactor {
    function getConversionFactor(address _pod)
        external
        view
        virtual
        override
        returns (uint256 _factor, uint256 _denomenator)
    {
        (_factor, _denomenator) = _calculateCbrWithDen(_pod);
    }

    function _calculateCbrWithDen(address _pod) internal view returns (uint256, uint256) {
        require(IDecentralizedIndex(_pod).unlocked() == 1, "OU");
        uint256 _den = 10 ** 18;
        return (IDecentralizedIndex(_pod).convertToAssets(_den), _den);
    }
}
