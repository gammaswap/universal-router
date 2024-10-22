// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '../UniversalRouter.sol';

contract TestUniversalRouter is UniversalRouter {

    using BytesLib2 for bytes;
    using Path2 for bytes;

    constructor(address _WETH) UniversalRouter(_WETH) {
    }

    function _getTokenOut(bytes memory path) public virtual pure returns(address tokenOut) {
        bytes memory _path = path;
        while (_path.hasMultiplePools()) {
            _path = _path.skipToken();
        }
        tokenOut = _path.skipToken().toAddress(0);
    }
}
