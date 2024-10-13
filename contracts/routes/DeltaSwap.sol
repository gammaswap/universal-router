pragma solidity ^0.8.0;

import "@gammaswap/v1-deltaswap/contracts/libraries/DSMath.sol";
import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapPair.sol";

import "./UniswapV2.sol";

contract DeltaSwap is UniswapV2 {

    constructor(uint16 _protocolId, address _factory) UniswapV2(_protocolId, _factory) {
    }

    function initCodeHash() internal override pure returns(bytes32) {
        return 0xa82767a5e39a2e216962a2ebff796dcc37cd05dfd6f7a149e1f8fbb6bf487658;
    }

    function getAmountOut(uint256 amountIn, address tokenA, address tokenB, uint16 protocolId, uint256 fee) public override virtual
        returns(uint256 amountOut, address pair, uint24 swapFee) {
        uint256 reserveIn;
        uint256 reserveOut;
        (reserveIn, reserveOut, pair) = getReserves(tokenA, tokenB);
        swapFee = uint24(calcPairTradingFee(amountIn, reserveIn, reserveOut, pair)); // for information purposes only, matches UniV3 format
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut, swapFee);
    }

    function getAmountIn(uint256 amountOut, address tokenA, address tokenB, uint16 protocolId, uint256 fee) public override virtual
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

    function calcPairTradingFee(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, address pair) internal view returns(uint256 fee) {
        uint256 tradeLiquidity = DSMath.calcTradeLiquidity(amountIn, 0, reserveIn, reserveOut);
        fee = IDeltaSwapPair(pair).estimateTradingFee(tradeLiquidity);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint256 fee) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'DeltaSwapLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'DeltaSwapLibrary: INSUFFICIENT_LIQUIDITY');
        uint256 amountInWithFee = amountIn * (1000 - fee);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint256 fee) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, 'DeltaSwapLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'DeltaSwapLibrary: INSUFFICIENT_LIQUIDITY');
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * (1000 - fee);
        amountIn = (numerator / denominator) + 1;
    }
}
