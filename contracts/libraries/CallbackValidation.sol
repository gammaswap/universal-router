// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import './PoolAddress.sol';

/// @notice Provides validation for callbacks from Uniswap V3 Pools
library CallbackValidation {
    /// @notice Returns the address of a valid Uniswap V3 Pool
    /// @param factory The contract address of the Uniswap V3 factory
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param initCodeHash init code hash of the V3 pool
    /// @return pool The V3 pool contract address
    function verifyCallback(
        address factory,
        address tokenA,
        address tokenB,
        uint24 fee,
        bytes32 initCodeHash
    ) internal view returns (address pool) {
        return verifyCallback(factory, initCodeHash, PoolAddress.getPoolKey(tokenA, tokenB, fee));
    }

    /// @notice Returns the address of a valid Uniswap V3 Pool
    /// @param factory The contract address of the Uniswap V3 factory
    /// @param initCodeHash init code hash of the V3 pool
    /// @param poolKey The identifying key of the V3 pool
    /// @return pool The V3 pool contract address
    function verifyCallback(address factory, bytes32 initCodeHash, PoolAddress.PoolKey memory poolKey)
    internal
    view
    returns (address pool)
    {
        pool = PoolAddress.computeAddress(factory, initCodeHash, poolKey);
        require(msg.sender == address(pool));
    }
}