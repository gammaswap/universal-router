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
}
