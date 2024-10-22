// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title Aerodrome Library
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Aerodrome mathematical calculations for swapping stable and non stable token pools
/// @dev Stable token pools are based on stable-swap model
library AeroLib {

    /// @dev Given an input amount of an asset and pair reserves, returns a required output amount of the other asset
    /// @param amountIn - amount desired to swap in to calculate amount that will be swapped out
    /// @param reserveIn - reserve amount of token swapped in
    /// @param reserveOut - reserve amount of token swapped out
    /// @param decimalsIn - decimal expansion of tokenIn (e.g. 10^18 if 18 decimals token)
    /// @param decimalsOut - decimal expansion of tokenOut (e.g. 10^18 if 18 decimals token)
    /// @param stable - true if it's a stable token pool
    /// @param fee - fee charged for swap
    /// @return amountOut - amount of token to receive for amountIn
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut,
        uint256 decimalsIn, uint256 decimalsOut, bool stable, uint256 fee) internal view returns (uint256) {
        amountIn -= (amountIn * fee) / 10000; // remove fee from amount received
        if(stable) {
            return _getAmountOutStable(amountIn, reserveIn, reserveOut, decimalsIn, decimalsOut);
        } else {
            return _getAmountOutNonStable(amountIn, reserveIn, reserveOut);
        }
    }

    /// @dev Given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    /// @param amountOut - amount desired to swap out
    /// @param reserveIn - reserve amount of token swapped in
    /// @param reserveOut - reserve amount of token swapped out
    /// @param decimalsIn - decimal expansion of tokenIn (e.g. 10^18 if 18 decimals token)
    /// @param decimalsOut - decimal expansion of tokenOut (e.g. 10^18 if 18 decimals token)
    /// @param stable - true if it's a stable token pool
    /// @param fee - fee charged for swap
    /// @return amountIn - amount of token to swap in to get amountOut
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut,
        uint256 decimalsIn, uint256 decimalsOut, bool stable, uint256 fee) internal view returns (uint256) {
        if(stable) {
            return _getAmountInStable(amountOut, reserveOut, reserveIn, decimalsOut, decimalsIn) * 10000 / (10000 - fee) + 1;
        } else {
            return _getAmountInNonStable(amountOut, reserveOut, reserveIn) * 10000 / (10000 - fee) + 1;
        }
    }

    /// @dev Given an input amount of an asset and pair reserves, returns a required output amount of the other asset in a stable token pool
    /// @param amountIn - amount desired to swap in to calculate amount that will be swapped out
    /// @param reserveIn - reserve amount of token swapped in
    /// @param reserveOut - reserve amount of token swapped out
    /// @param decimalsIn - decimal expansion of tokenIn (e.g. 10^18 if 18 decimals token)
    /// @param decimalsOut - decimal expansion of tokenOut (e.g. 10^18 if 18 decimals token)
    /// @return amountOut - amount of token to receive for amountIn
    function _getAmountOutStable(uint256 amountIn, uint256 reserveIn, uint256 reserveOut,
        uint256 decimalsIn, uint256 decimalsOut) internal view returns (uint256) {
        uint256 xy = _k(reserveIn, reserveOut, decimalsIn, decimalsOut, true);
        reserveIn = (reserveIn * 1e18) / decimalsIn;
        reserveOut = (reserveOut * 1e18) / decimalsOut;
        amountIn = (amountIn * 1e18) / decimalsIn;
        uint256 y = reserveOut - _get_y(amountIn + reserveIn, xy, reserveOut, decimalsIn, decimalsOut);
        return (y * (decimalsOut)) / 1e18;
    }

    /// @dev Given an input amount of an asset and pair reserves, returns a required output amount of the other asset in a non-stable token pool
    /// @param amountIn - amount desired to swap in to calculate amount that will be swapped out
    /// @param reserveIn - reserve amount of token swapped in
    /// @param reserveOut - reserve amount of token swapped out
    /// @return amountOut - amount of token to receive for amountIn
    function _getAmountOutNonStable(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal view returns (uint256) {
        return (amountIn * reserveOut) / (reserveIn + amountIn);
    }

    /// @dev Given an output amount of an asset and pair reserves, returns a required input amount of the other asset in stable token pool
    /// @param amountOut - amount desired to swap out
    /// @param reserveIn - reserve amount of token swapped in
    /// @param reserveOut - reserve amount of token swapped out
    /// @param decimalsIn - decimal expansion of tokenIn (e.g. 10^18 if 18 decimals token)
    /// @param decimalsOut - decimal expansion of tokenOut (e.g. 10^18 if 18 decimals token)
    /// @return amountIn - amount of token to swap in to get amountOut
    function _getAmountInStable(uint256 amountOut, uint256 reserveOut, uint256 reserveIn,
        uint256 decimalsOut, uint256 decimalsIn) internal view returns (uint256) {
        uint256 xy = _k(reserveOut, reserveIn, decimalsOut, decimalsIn, true);
        reserveOut = (reserveOut * 1e18) / decimalsOut;
        reserveIn = (reserveIn * 1e18) / decimalsIn;
        amountOut = (amountOut * 1e18) / decimalsOut;
        uint256 y = _get_y(reserveOut - amountOut, xy, reserveIn, decimalsOut, decimalsIn) - reserveIn;
        return (y * (decimalsIn)) / 1e18;
    }

    /// @dev Given an output amount of an asset and pair reserves, returns a required input amount of the other asset in a non-stable token pool
    /// @param amountOut - amount desired to swap out
    /// @param reserveIn - reserve amount of token swapped in
    /// @param reserveOut - reserve amount of token swapped out
    /// @return amountIn - amount of token to swap in to get amountOut
    function _getAmountInNonStable(uint256 amountOut, uint256 reserveOut, uint256 reserveIn) internal view returns (uint256) {
        return (amountOut * reserveIn) / (reserveOut - amountOut);
    }

    /// @dev Calculate leveraged amount of token Y in pool based on amount of X. Used in stable token pools
    /// @param x0 - amount of token X in pool
    /// @param xy - amount of token X times amount of token Y
    /// @param y - amount of token Y in stable pool
    /// @param decimalsX - decimal expansion of token X (e.g. 10^18 if 18 decimals token)
    /// @param decimalsY - decimal expansion of token Y (e.g. 10^18 if 18 decimals token)
    /// @return leveraged amount of token Y in stable token pool
    function _get_y(uint256 x0, uint256 xy, uint256 y, uint256 decimalsX, uint256 decimalsY) internal view returns (uint256) {
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
                    if (_k(x0, y + 1, decimalsX, decimalsY, true) > xy) {
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
        revert('!y');
    }

    /// @dev calculate stable-swap invariant assuming x0 and y are already normalized to 18 decimal tokens
    function _f(uint256 x0, uint256 y) internal pure returns (uint256) {
        uint256 _a = (x0 * y) / 1e18;
        uint256 _b = ((x0 * x0) / 1e18 + (y * y) / 1e18);
        return (_a * _b) / 1e18;
    }

    /// @dev calculate delta change in token Y
    function _d(uint256 x0, uint256 y) internal pure returns (uint256) {
        return (3 * x0 * ((y * y) / 1e18)) / 1e18 + ((((x0 * x0) / 1e18) * x0) / 1e18);
    }

    /// @dev calculate stable-swap invariant when it's a stable token pool. Normalize to 18 decimals
    /// @dev calculate constant product market maker invariant when not a stable token pool
    function _k(uint256 x, uint256 y, uint256 decimalsX, uint256 decimalsY, bool stable) internal view returns (uint256) {
        if (stable) {
            uint256 _x = (x * 1e18) / decimalsX;
            uint256 _y = (y * 1e18) / decimalsY;
            uint256 _a = (_x * _y) / 1e18;
            uint256 _b = ((_x * _x) / 1e18 + (_y * _y) / 1e18);
            return (_a * _b) / 1e18; // x3y+y3x >= k
        } else {
            return x * y; // xy >= k
        }
    }
}
