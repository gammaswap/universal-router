// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@gammaswap/v1-periphery/contracts/base/Transfers.sol";

import './libraries/BytesLib2.sol';
import './libraries/Path2.sol';
import './interfaces/IProtocolRoute.sol';

abstract contract BaseRouter is Transfers {

    using BytesLib2 for bytes;
    using Path2 for bytes;

    constructor(address _WETH) Transfers(_WETH) {
    }

    function _getTokenOut(bytes memory path) public view returns(address tokenOut) {
        bytes memory _path = path;
        while (_path.hasMultiplePools()) {
            _path = _path.skipToken();
        }
        tokenOut = _path.skipToken().toAddress(0);
    }

    function getGammaPoolAddress(address cfmm, uint16 protocolId) internal override virtual view returns(address) {
        return address(0);
    }

    function sendTokensCallback(address[] calldata tokens, uint256[] calldata amounts, address payee, bytes calldata data) external virtual override {
    }
}
