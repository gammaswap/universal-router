// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@gammaswap/v1-deltaswap/contracts/libraries/DSMath.sol";
import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapPair.sol";

library DSLib {

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint256 fee) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'DeltaSwapLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'DeltaSwapLibrary: INSUFFICIENT_LIQUIDITY');
        uint256 amountInWithFee = amountIn * (1000 - fee);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint256 fee) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, 'DeltaSwapLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'DeltaSwapLibrary: INSUFFICIENT_LIQUIDITY');
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * (1000 - fee);
        amountIn = (numerator / denominator) + 1;
    }

    function calcPairTradingFee(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, address pair) internal view returns(uint256 fee) {
        uint256 tradeLiquidity = DSMath.calcTradeLiquidity(amountIn, 0, reserveIn, reserveOut);
        fee = IDeltaSwapPair(pair).estimateTradingFee(tradeLiquidity);
    }
}
