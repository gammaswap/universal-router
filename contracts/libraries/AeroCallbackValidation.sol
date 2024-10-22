// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '../interfaces/external/IAeroCLPool.sol';
import './AeroPoolAddress.sol';

/// @notice Provides validation for callbacks from CL Pools
library AeroCallbackValidation {
    /// @notice Returns the address of a valid CL Pool
    /// @param factory The contract address of the CL factory
    /// @param tokenA The contract address of either token0 or token1
    /// @param tokenB The contract address of the other token
    /// @param tickSpacing The tick spacing for the pool
    /// @return pool The V3 pool contract address
    function verifyCallback(address factory, address tokenA, address tokenB, int24 tickSpacing)
    internal
    view
    returns (IAeroCLPool pool)
    {
        return verifyCallback(factory, AeroPoolAddress.getPoolKey(tokenA, tokenB, tickSpacing));
    }

    /// @notice Returns the address of a valid CL Pool
    /// @param factory The contract address of the CL factory
    /// @param poolKey The identifying key of the V3 pool
    /// @return pool The V3 pool contract address
    function verifyCallback(address factory, AeroPoolAddress.PoolKey memory poolKey) internal view returns (IAeroCLPool pool) {
        pool = IAeroCLPool(AeroPoolAddress.computeAddress(factory, poolKey));
        require(msg.sender == address(pool));
    }
}