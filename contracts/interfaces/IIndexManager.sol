// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IDecentralizedIndex.sol";

interface IIndexManager {
    struct IIndexAndStatus {
        address index; // aka pod
        address creator;
        bool verified; // whether it's a safe pod as confirmed by the protocol team
        bool selfLending; // if it's an LVF pod, whether it's self-lending or not
        bool makePublic; // whether it should show in the UI or not
    }

    event AddIndex(address indexed index, bool verified);

    event RemoveIndex(address indexed index);

    event SetVerified(address indexed index, bool verified);

    function allIndexes() external view returns (IIndexAndStatus[] memory);

    function addIndex(address index, address _creator, bool verified, bool selfLending, bool makePublic) external;

    function removeIndex(uint256 idx) external;

    function verifyIndex(uint256 idx, bool verified) external;

    function deployNewIndex(
        string memory indexName,
        string memory indexSymbol,
        bytes memory baseConfig,
        bytes memory immutables
    ) external returns (address _index);
}
