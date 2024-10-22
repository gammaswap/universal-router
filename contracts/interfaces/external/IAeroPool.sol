// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title Interface for the Aerodrome Pool within UniversalRouter
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @dev This is a limited implementation for use in UniversalRouter. Sufficient to perform swaps
interface IAeroPool {
    /// @notice Read reserve token quantities in the AMM, and timestamp of last update
    /// @dev Reserve quantities come back as uint112 although we store them as uint128
    /// @return reserve0 - quantity of token0 held in AMM
    /// @return reserve1 - quantity of token1 held in AMM
    /// @return blockTimestampLast - timestamp of the last update block
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1, uint256 blockTimestampLast);

    /// @notice Get the amount of tokenOut given the amount of tokenIn
    /// @param amountIn Amount of token in
    /// @param tokenIn  Address of token
    /// @return Amount out
    function getAmountOut(uint256 amountIn, address tokenIn) external view returns (uint256);

    /// @notice Exchange one token for another token, must send token amount to exchange first before calling this function
    /// @dev The user specifies which token amount to get. Therefore only one token amount parameter is greater than zero
    /// @param amount0Out - address that will receive reserve tokens
    /// @param amount1Out - address that will receive reserve tokens
    /// @param to - address that will receive output token quantity
    /// @param data - used for flash loan trades
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}
