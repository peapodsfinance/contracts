// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

// https://github.com/velodrome-finance/slipstream/blob/main/contracts/core/interfaces/ICLFactory.sol
interface ICLFactory {
    function poolImplementation() external view returns (address);
}
