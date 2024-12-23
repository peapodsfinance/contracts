// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDIAOracleV2} from "../../contracts/interfaces/IDIAOracleV2.sol";

contract MockDIAOracleV2 is IDIAOracleV2 {
    mapping(string => uint128) private prices;
    mapping(string => uint128) private timestamps;

    error KeyNotSet(string key);

    /// @notice Sets a price and timestamp for a given key
    /// @param key The key to set the price for
    /// @param price The price to set
    /// @param timestamp The timestamp to set
    function setValue(string memory key, uint128 price, uint128 timestamp) external {
        prices[key] = price;
        timestamps[key] = timestamp;
    }

    /// @notice Gets the price and timestamp for a given key
    /// @param key The key to get the price for
    /// @return price The price for the given key
    /// @return timestamp The timestamp for the given key
    function getValue(string memory key) external view returns (uint128 price, uint128 timestamp) {
        price = prices[key];
        timestamp = timestamps[key];

        if (price == 0) {
            revert KeyNotSet(key);
        }

        return (price, timestamp);
    }
}
