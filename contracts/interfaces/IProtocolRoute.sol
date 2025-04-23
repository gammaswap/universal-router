// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

/// @title Protocol Route Interface
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Interface for ProtocolRoute contracts
/// @dev Every protocol route created must implement this interface
interface IProtocolRoute {

    /// @dev Unique across protocol routes. Matches protocolId in GammaSwap
    /// @return id of protocol route
    function protocolId() external view returns(uint16);

    /// @return factory contract of AMMs for this route
    function factory() external view returns(address);

    /// @dev Get AMM for tokenA and tokenB pair.
    /// @param tokenA - address of a token of the AMM pool
    /// @param tokenB - address of other token of the AMM pool
    /// @param fee - AMM fee used to identify AMM pool
    /// @return pair - address of AMM for token pair
    /// @return token0 - address of token0 in AMM
    /// @return token1 - address of token1 in AMM
    function pairFor(address tokenA, address tokenB, uint24 fee) external view returns (address pair, address token0, address token1);

    /// @dev Get conversion amount of amountIn of tokenIn in tokenOut. Conversion happens at marginal price of AMM
    /// @param amountIn - quantity of tokenIn token to convert to tokenOut
    /// @param tokenIn - address token of amountIn quantity that will be converted
    /// @param tokenOut - address of token that amountIn in tokenIn will be converted to
    /// @param fee - fee of AMM pair
    /// @return amountOut - quantity of amountIn is converted to in tokenOut at marginal price between tokenIn and tokenOut
    function quote(uint256 amountIn, address tokenIn, address tokenOut, uint24 fee) external view returns (uint256 amountOut);

    /// @dev Get fee charged by AMM pair as an integer. Divide by 1e6 to convert to decimal
    /// @param tokenIn - address token of amountIn quantity that will be converted
    /// @param tokenOut - address of token that amountIn in tokenIn will be converted to
    /// @param fee - fee identifier of AMM pair
    /// @return total fee charged by AMM in integer form
    function getFee(address tokenIn, address tokenOut, uint24 fee) external view returns (uint256);

    /// @dev Get expected amount in tokenOut that amount in tokenIn will be converted to
    /// @param amountIn - quantity of tokenIn token to convert to tokenOut
    /// @param tokenIn - address token of amountIn quantity that will be converted
    /// @param tokenOut - address of token that amountIn in tokenIn will be converted to
    /// @param fee - fee of AMM pair
    /// @return amountOut - quantity of amountIn is converted to in tokenOut between tokenIn and tokenOut (takes slippage into account)
    /// @return pair - address of AMM for tokenIn and tokenOut used to perform swap
    /// @return swapFee - fee charged to swap by AMM pair contract
    function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut, uint256 fee) external
        returns(uint256 amountOut, address pair, uint24 swapFee);

    /// @dev Get expected amount in tokenOut that amount in tokenIn will be converted to. Zero amountIn is acceptable result
    /// @param amountIn - quantity of tokenIn token to convert to tokenOut
    /// @param tokenIn - address token of amountIn quantity that will be converted
    /// @param tokenOut - address of token that amountIn in tokenIn will be converted to
    /// @param fee - fee of AMM pair
    /// @return amountOut - quantity of amountIn is converted to in tokenOut between tokenIn and tokenOut (takes slippage into account)
    /// @return pair - address of AMM for tokenIn and tokenOut used to perform swap
    /// @return swapFee - fee charged to swap by AMM pair contract
    function getAmountOutNoSwap(uint256 amountIn, address tokenIn, address tokenOut, uint256 fee) external
        returns(uint256 amountOut, address pair, uint24 swapFee);

    /// @dev Get expected amount in tokenIn that must be swapped in to get amountOut in tokenOut
    /// @param amountIn - quantity of tokenIn token to convert to tokenOut
    /// @param tokenIn - address token of amountIn quantity that will be converted
    /// @param tokenOut - address of token that amountIn in tokenIn will be converted to
    /// @param fee - fee of AMM pair
    /// @return amountIn - quantity of tokenIn token to swap in to get amountOut in tokenOut (takes slippage into account)
    /// @return pair - address of AMM for tokenIn and tokenOut used to perform swap
    /// @return swapFee - fee charged to swap by AMM pair contract
    function getAmountIn(uint256 amountOut, address tokenIn, address tokenOut, uint256 fee) external
        returns(uint256 amountIn, address pair, uint24 swapFee);

    /// @dev Get address funding the swap in the AMM identified by tokenA, tokenB, and fee
    /// @param tokenA - address of tokenA in AMM
    /// @param tokenB - address of tokenB in AMM
    /// @param fee - fee of AMM pair
    /// @return pair - address of AMM contract for tokenA, tokenB, and fee
    /// @return origin - address funding the AMM swap
    function getOrigin(address tokenA, address tokenB, uint24 fee) external view returns(address, address);

    /// @dev Perform swap in AMM from token `from` to token `to`
    /// @param from - address of funding token in the swap
    /// @param to - address of token to receive from the swap
    /// @param fee - fee of the AMM (used only in protocols such as UniswapV3)
    /// @param dest - address that will receive output of the swap
    function swap(address from, address to, uint24 fee, address dest) external;
}
