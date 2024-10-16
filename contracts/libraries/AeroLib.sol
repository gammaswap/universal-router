// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

library AeroLib {

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut,
        uint256 decimalsIn, uint256 decimalsOut, bool stable, uint256 fee) internal view returns (uint256) {
        amountIn -= (amountIn * fee) / 10000; // remove fee from amount received
        if(stable) {
            return _getAmountOutStable(amountIn, reserveIn, reserveOut, decimalsIn, decimalsOut);
        } else {
            return _getAmountOutNonStable(amountIn, reserveIn, reserveOut);
        }
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut,
        uint256 decimalsIn, uint256 decimalsOut, bool stable, uint256 fee) internal view returns (uint256) {
        if(stable) {
            return _getAmountInStable(amountOut, reserveOut, reserveIn, decimalsOut, decimalsIn) * 10000 / (10000 - fee) + 1;
        } else {
            return _getAmountInNonStable(amountOut, reserveOut, reserveIn) * 10000 / (10000 - fee) + 1;
        }
    }

    function _getAmountOutStable(uint256 amountIn, uint256 reserveIn, uint256 reserveOut,
        uint256 decimalsIn, uint256 decimalsOut) internal view returns (uint256) {
        uint256 xy = _k(reserveIn, reserveOut, decimalsIn, decimalsOut, true);
        reserveIn = (reserveIn * 1e18) / decimalsIn;
        reserveOut = (reserveOut * 1e18) / decimalsOut;
        amountIn = (amountIn * 1e18) / decimalsIn;
        uint256 y = reserveOut - _get_y(amountIn + reserveIn, xy, reserveOut, decimalsIn, decimalsOut);
        return (y * (decimalsOut)) / 1e18;
    }

    function _getAmountOutNonStable(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal view returns (uint256) {
        return (amountIn * reserveOut) / (reserveIn + amountIn);
    }

    function _getAmountInStable(uint256 amountOut, uint256 reserveOut, uint256 reserveIn,
        uint256 decimalsOut, uint256 decimalsIn) internal view returns (uint256) {
        uint256 xy = _k(reserveOut, reserveIn, decimalsOut, decimalsIn, true);
        reserveOut = (reserveOut * 1e18) / decimalsOut;
        reserveIn = (reserveIn * 1e18) / decimalsIn;
        amountOut = (amountOut * 1e18) / decimalsOut;
        uint256 y = _get_y(reserveOut - amountOut, xy, reserveIn, decimalsOut, decimalsIn) - reserveIn;
        return (y * (decimalsIn)) / 1e18;
    }

    function _getAmountInNonStable(uint256 amountOut, uint256 reserveOut, uint256 reserveIn) internal view returns (uint256) {
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
        revert("!y");
    }

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
