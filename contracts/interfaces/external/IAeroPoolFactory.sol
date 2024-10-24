// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

/// @title Interface for the Aerodrome Pool Factory within UniversalRouter
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice The AMM Factory facilitates creation of Aerodrome pools
/// @dev This is a limited implementation for use in UniversalRouter
/// @dev Write functions are defined only for unit testing
interface IAeroPoolFactory {

    event SetFeeManager(address feeManager);
    event SetPauser(address pauser);
    event SetPauseState(bool state);
    event SetVoter(address voter);
    event PoolCreated(address indexed token0, address indexed token1, bool indexed stable, address pool, uint256);
    event SetCustomFee(address indexed pool, uint256 fee);

    /// @notice Returns address of implementation Aerodrome pool contract from which all AMMs are made
    function implementation() external view returns (address);

    /// @notice Returns fee for a pool, as custom fees are possible.
    function getFee(address _pool, bool _stable) external view returns (uint256);

    /// @notice Return address of pool created by this factory
    /// @param tokenA .
    /// @param tokenB .
    /// @param stable True if stable, false if volatile
    function getPool(address tokenA, address tokenB, bool stable) external view returns (address);

    /// @notice Create a pool given two tokens and if they're stable/volatile
    /// @dev token order does not matter
    /// @param tokenA .
    /// @param tokenB .
    /// @param stable .
    function createPool(address tokenA, address tokenB, bool stable) external returns (address pool);
}
