// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

/// @title Provides functions for deriving a pool address from the deployer, tokens, and the fee
library PoolAddressShadow {
    bytes32 internal constant POOL_INIT_CODE_HASH = 0xc701ee63862761c31d620a4a083c61bdc1e81761e6b9c9267fd19afd22e0821d;

    /// @notice The identifying key of the pool
    struct PoolKey {
        address token0;
        address token1;
        int24 tickSpacing;
    }

    /// @notice Returns PoolKey: the ordered tokens with the matched fee levels
    /// @param tokenA The first token of a pool, unsorted
    /// @param tokenB The second token of a pool, unsorted
    /// @param tickSpacing The tickSpacing of the pool
    /// @return Poolkey The pool details with ordered token0 and token1 assignments
    function getPoolKey(address tokenA, address tokenB, int24 tickSpacing) internal pure returns (PoolKey memory) {
        if (tokenA > tokenB) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey({token0: tokenA, token1: tokenB, tickSpacing: tickSpacing});
    }

    /// @notice Deterministically computes the pool address given the deployer and PoolKey
    /// @param deployer The Uniswap V3 deployer contract address
    /// @param key The PoolKey
    /// @return pool The contract address of the V3 pool
    function computeAddress(address deployer, PoolKey memory key) internal pure returns (address pool) {
        require(key.token0 < key.token1, "!TokenOrder");
        pool = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            deployer,
                            keccak256(abi.encode(key.token0, key.token1, key.tickSpacing)),
                            POOL_INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }
}
