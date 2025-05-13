// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '../UniversalRouterSplit.sol';

contract TestUniversalRouter2 is UniversalRouterSplit {

    using BytesLib2 for bytes;
    using Path2 for bytes;

    constructor(address _WETH) UniversalRouterSplit(_WETH) {
    }

    function validatePathsAndWeights(bytes[] memory paths, uint256[] memory weights, uint8 swapType) external virtual {
        _validatePathsAndWeights(paths, weights, swapType);
    }

    function splitAmount(uint256 amount, uint256[] memory weights) external view returns (uint256[] memory amounts) {
        return _splitAmount(amount, weights);
    }

    function getAmountsOut(uint256 amountIn, bytes memory path) public override virtual
        returns (uint256[] memory amounts, Route[] memory routes) {
    }

    function getAmountsOutNoSwap(uint256 amountIn, bytes memory path) public override
        virtual returns ( uint256[] memory amounts, Route[] memory routes) {
    }

    function getAmountsIn(uint256 amountOut, bytes memory path) public override virtual returns (uint256[] memory amounts, Route[] memory routes) {
    }

    function externalCall(address sender, uint128[] calldata amounts, uint256 lpTokens, bytes calldata _data) external override virtual {
    }
}
