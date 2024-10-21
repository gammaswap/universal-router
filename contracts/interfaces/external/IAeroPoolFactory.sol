// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IAeroPoolFactory {

    function implementation() external view returns (address);

    /// @notice Returns fee for a pool, as custom fees are possible.
    function getFee(address _pool, bool _stable) external view returns (uint256);

    /// @notice Return address of pool created by this factory
    /// @param tokenA .
    /// @param tokenB .
    /// @param stable True if stable, false if volatile
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address);

    function createPool(address tokenA, address tokenB, bool stable) external returns (address pool);
}
