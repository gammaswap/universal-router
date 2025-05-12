// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '../UniversalRouter.sol';

contract TestUniversalRouter2 is UniversalRouter {

    using BytesLib2 for bytes;
    using Path2 for bytes;

    constructor(address _WETH) UniversalRouter(_WETH) {
    }

    function validatePathsAndWeights(bytes[] memory paths, uint256[] memory weights, uint8 swapType) external virtual {
        _validatePathsAndWeights(paths, weights, swapType);
    }

    function calcSplitAmountsIn(uint256 amountIn, uint256[] memory weights) external view returns (uint256[] memory amountsIn) {
        return _calcSplitAmountsIn(amountIn, weights);
    }

    function getAmountsOutSplit(uint256 amountIn, bytes[] memory path, uint256[] memory weights) public override virtual
        returns (uint256 amountOut, uint256[][] memory amountsSplit, Route[][] memory routesSplit) {
    }

    function getAmountsOutSplitNoSwap(uint256 amountIn, bytes[] memory path, uint256[] memory weights) public override
        virtual returns (uint256 amountOut, uint256[][] memory amountsSplit, Route[][] memory routesSplit) {
    }
}
