// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library AeroLib {

    function getAmountOut(uint256 amountIn, address tokenIn, address token0, uint256 reserve0, uint256 reserve1,
        uint256 decimals0, uint256 decimals1, bool stable, uint256 fee) internal view returns (uint256) {
        (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
        amountIn -= (amountIn * fee) / 10000; // remove fee from amount received
        if(stable) {
            return _getAmountOutStable(amountIn, tokenIn, token0, _reserve0, _reserve1, decimals0, decimals1);
        } else {
            return _getAmountOutNonStable(amountIn, tokenIn, token0, _reserve0, _reserve1);
        }
    }

    function getAmountIn(uint256 amountOut, address tokenOut, address token0, uint256 reserve0, uint256 reserve1,
        uint256 decimals0, uint256 decimals1, bool stable, uint256 fee) internal view returns (uint256) {
        (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
        amountOut -= (amountOut * fee) / 10000; //TODO must update logic to account for fee same as in UniswapV2
        if(stable) {
            return _getAmountInStable(amountOut, tokenOut, token0, _reserve0, _reserve1, decimals0, decimals1);
        } else {
            return _getAmountInNonStable(amountOut, tokenOut, token0, _reserve0, _reserve1);
        }
    }

    // TODO: must make sure decimals match order
    function _getAmountOutStable(uint256 amountIn, address tokenIn, address token0, uint256 _reserve0, uint256 _reserve1,
        uint256 decimals0, uint256 decimals1) internal view returns (uint256) {
        uint256 xy = _k(_reserve0, _reserve1, decimals0, decimals1, true);
        _reserve0 = (_reserve0 * 1e18) / decimals0;
        _reserve1 = (_reserve1 * 1e18) / decimals1;
        (uint256 reserveA, uint256 reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
        amountIn = tokenIn == token0 ? (amountIn * 1e18) / decimals0 : (amountIn * 1e18) / decimals1;
        uint256 y = reserveB - _get_y(amountIn + reserveA, xy, reserveB, decimals0, decimals1);
        return (y * (tokenIn == token0 ? decimals1 : decimals0)) / 1e18;
    }

    function _getAmountOutNonStable(uint256 amountIn, address tokenIn, address token0, uint256 _reserve0, uint256 _reserve1
    ) internal view returns (uint256) {
        (uint256 reserveA, uint256 reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
        return (amountIn * reserveB) / (reserveA + amountIn);
    }

    // TODO: must make sure decimals match order
    function _getAmountInStable(uint256 amountOut, address tokenOut, address token0, uint256 _reserve0, uint256 _reserve1,
        uint256 decimals0, uint256 decimals1) internal view returns (uint256) {
        uint256 xy = _k(_reserve0, _reserve1, decimals0, decimals1, true);
        _reserve0 = (_reserve0 * 1e18) / decimals0;
        _reserve1 = (_reserve1 * 1e18) / decimals1;
        (uint256 reserveA, uint256 reserveB) = tokenOut == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
        amountOut = tokenOut == token0 ? (amountOut * 1e18) / decimals0 : (amountOut * 1e18) / decimals1;
        uint256 y = _get_y(reserveA - amountOut, xy, reserveB, decimals0, decimals1) - reserveB;
        return (y * (tokenOut == token0 ? decimals1 : decimals0)) / 1e18;
    }

    function _getAmountInNonStable(uint256 amountOut, address tokenOut, address token0,
        uint256 _reserve0, uint256 _reserve1
    ) internal view returns (uint256) {
        (uint256 reserveOut, uint256 reserveIn) = tokenOut == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
        return (amountOut * reserveIn) / (reserveOut - amountOut);
    }

    function _f(uint256 x0, uint256 y) internal pure returns (uint256) {
        uint256 _a = (x0 * y) / 1e18;
        uint256 _b = ((x0 * x0) / 1e18 + (y * y) / 1e18);
        return (_a * _b) / 1e18;
    }

    function _d(uint256 x0, uint256 y) internal pure returns (uint256) {
        return (3 * x0 * ((y * y) / 1e18)) / 1e18 + ((((x0 * x0) / 1e18) * x0) / 1e18);
    }

    function _get_y(uint256 x0, uint256 xy, uint256 y, uint256 decimals0, uint256 decimals1) internal view returns (uint256) {
        for (uint256 i = 0; i < 255; i++) {
            uint256 k = _f(x0, y);
            if (k < xy) {
                // there are two cases where dy == 0
                // case 1: The y is converged and we find the correct answer
                // case 2: _d(x0, y) is too large compare to (xy - k) and the rounding error
                //         screwed us.
                //         In this case, we need to increase y by 1
                uint256 dy = ((xy - k) * 1e18) / _d(x0, y);
                if (dy == 0) {
                    if (k == xy) {
                        // We found the correct answer. Return y
                        return y;
                    }
                    if (_k(x0, y + 1, decimals0, decimals1, true) > xy) {
                        // If _k(x0, y + 1) > xy, then we are close to the correct answer.
                        // There's no closer answer than y + 1
                        return y + 1;
                    }
                    dy = 1;
                }
                y = y + dy;
            } else {
                uint256 dy = ((k - xy) * 1e18) / _d(x0, y);
                if (dy == 0) {
                    if (k == xy || _f(x0, y - 1) < xy) {
                        // Likewise, if k == xy, we found the correct answer.
                        // If _f(x0, y - 1) < xy, then we are close to the correct answer.
                        // There's no closer answer than "y"
                        // It's worth mentioning that we need to find y where f(x0, y) >= xy
                        // As a result, we can't return y - 1 even it's closer to the correct answer
                        return y;
                    }
                    dy = 1;
                }
                y = y - dy;
            }
        }
        revert("!y");
    }

    function _k(uint256 x, uint256 y, uint256 decimals0, uint256 decimals1, bool stable) internal view returns (uint256) {
        if (stable) {
            uint256 _x = (x * 1e18) / decimals0;
            uint256 _y = (y * 1e18) / decimals1;
            uint256 _a = (_x * _y) / 1e18;
            uint256 _b = ((_x * _x) / 1e18 + (_y * _y) / 1e18);
            return (_a * _b) / 1e18; // x3y+y3x >= k
        } else {
            return x * y; // xy >= k
        }
    }

    /// TODO: Must incorporate this logic in the quoting logic for AeroDrome stable pools
    function quoteStableLiquidityRatio(
        address tokenA,
        address tokenB,
        address _factory
    ) external view returns (uint256 ratio) {
        /*IPool pool = IPool(poolFor(tokenA, tokenB, true, _factory));

        uint256 decimalsA = 10 ** IERC20Metadata(tokenA).decimals();
        uint256 decimalsB = 10 ** IERC20Metadata(tokenB).decimals();

        uint256 investment = decimalsA;
        uint256 out = pool.getAmountOut(investment, tokenA);
        (uint256 amountA, uint256 amountB, ) = quoteAddLiquidity(tokenA, tokenB, true, _factory, investment, out);

        amountA = (amountA * 1e18) / decimalsA;
        amountB = (amountB * 1e18) / decimalsB;
        out = (out * 1e18) / decimalsB;
        investment = (investment * 1e18) / decimalsA;

        ratio = (((out * 1e18) / investment) * amountA) / amountB;

        return (investment * 1e18) / (ratio + 1e18);/**/
    }
}
