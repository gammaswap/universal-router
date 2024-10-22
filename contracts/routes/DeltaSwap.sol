// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import '@gammaswap/v1-deltaswap/contracts/libraries/DSMath.sol';
import '@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapPair.sol';

import './UniswapV2.sol';

/// @title DeltaSwap Protocol Route contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Route contract to implement swaps in DeltaSwap AMMs
/// @dev Implements IProtocolRoute functions to quote and handle one AMM swap at a time
contract DeltaSwap is UniswapV2 {

    /// @dev Initialize `_protocolId`, `_factory`, and `WETH` address
    constructor(uint16 _protocolId, address _factory, address _WETH) UniswapV2(_protocolId, _factory, _WETH) {
    }

    /// @dev init code hash of DeltaSwap pools. Used to calculate pool address without external calls
    function initCodeHash() internal override pure returns(bytes32) {
        return 0xa82767a5e39a2e216962a2ebff796dcc37cd05dfd6f7a149e1f8fbb6bf487658;
    }

    /// @inheritdoc IProtocolRoute
    function getAmountOut(uint256 amountIn, address tokenA, address tokenB, uint256 fee) public override virtual
        returns(uint256 amountOut, address pair, uint24 swapFee) {
        uint256 reserveIn;
        uint256 reserveOut;
        (reserveIn, reserveOut, pair) = getReserves(tokenA, tokenB);
        swapFee = uint24(calcPairTradingFee(amountIn, reserveIn, reserveOut, pair)); // for information purposes only, matches UniV3 format
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut, swapFee);
    }

    /// @inheritdoc IProtocolRoute
    function getAmountIn(uint256 amountOut, address tokenA, address tokenB, uint256 fee) public override virtual
        returns(uint256 amountIn, address pair, uint24 swapFee) {
        uint256 reserveIn;
        uint256 reserveOut;
        (reserveIn, reserveOut, pair) = getReserves(tokenA, tokenB);
        uint256 _fee = 3;
        while(true) {
            fee = _fee;
            amountIn = _getAmountIn(amountOut, reserveIn, reserveOut, fee);
            _fee = calcPairTradingFee(amountIn, reserveIn, reserveOut, pair);
            if(_fee == fee) break;
        }
        swapFee = uint24(fee);
    }

    /// @dev Calculate DeltaSwap pool trading fee
    /// @param amountIn - amount of token being swapped in
    /// @param reserveIn - reserve amount of token swapped in in AMM
    /// @param reserveOut - reserve amount of token swapped out from AMM
    /// @param pair - address of AMM pair
    /// @return fee - fee to perform swap
    function calcPairTradingFee(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, address pair) internal view returns(uint256 fee) {
        uint256 tradeLiquidity = DSMath.calcTradeLiquidity(amountIn, 0, reserveIn, reserveOut);
        fee = IDeltaSwapPair(pair).estimateTradingFee(tradeLiquidity);
    }

    /// @dev Given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    /// @param amountIn - amount of token being swapped in
    /// @param reserveIn - reserve amount of token swapped in
    /// @param reserveOut - reserve amount of token swapped out
    /// @param fee - fee to perform swap
    /// @return amountOut - amount of token being swapped out
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint256 fee) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'DeltaSwap: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'DeltaSwap: INSUFFICIENT_LIQUIDITY');
        uint256 amountInWithFee = amountIn * (1000 - fee);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @dev Given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    /// @param amountOut - amount desired to swap out
    /// @param reserveIn - reserve amount of token swapped in
    /// @param reserveOut - reserve amount of token swapped out
    /// @param fee - fee to perform swap
    /// @return amountIn - amount of token to swap in to get amountOut
    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint256 fee) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, 'DeltaSwap: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'DeltaSwap: INSUFFICIENT_LIQUIDITY');
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * (1000 - fee);
        amountIn = (numerator / denominator) + 1;
    }

    /// @inheritdoc IProtocolRoute
    function swap(address from, address to, uint24 fee, address dest) external override virtual {
        (address pair, address token0,) = pairFor(from, to);
        uint256 amountInput;
        uint256 amountOutput;
        { // scope to avoid stack too deep errors
            (uint256 reserveIn, uint256 reserveOut,) = getReserves(from, to);
            amountInput = GammaSwapLibrary.balanceOf(from, pair) - reserveIn;
            fee = uint24(calcPairTradingFee(amountInput, reserveIn, reserveOut, pair));
            amountOutput = _getAmountOut(amountInput, reserveIn, reserveOut, fee);
        }
        (uint256 amount0Out, uint256 amount1Out) = from == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
        IDeltaSwapPair(pair).swap(amount0Out, amount1Out, dest, new bytes(0));
    }
}
