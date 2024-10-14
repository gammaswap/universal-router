// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapPair.sol";
import "@gammaswap/v1-implementations/contracts/interfaces/external/cpmm/ICPMM.sol";
import "@gammaswap/v1-periphery/contracts/base/Transfers.sol";

import './libraries/BytesLib2.sol';
import './libraries/Path2.sol';
import './interfaces/IProtocolRoute.sol';

abstract contract BaseRouter is Transfers {

    using BytesLib2 for bytes;
    using Path2 for bytes;

    event ProtocolRegistered(uint16 indexed protocolId, address protocol);

    struct SwapCallbackData {
        bytes path;
        address payer;
    }

    struct Route {
        address pair;
        address from;
        address to;
        uint16 protocolId;
        uint24 fee;
        address dest;
        address hop;
    }

    mapping(uint16 => address) public protocols;

    constructor(address _WETH) Transfers(_WETH) {
    }

    function addProtocol(uint16 protocolId, address protocol) external virtual {
        require(protocolId > 0, "INVALID_PROTOCOL_ID");
        require(protocolId == IProtocolRoute(protocol).protocolId(), "PROTOCOL_ID_MATCH");
        protocols[protocolId] = protocol;
        emit ProtocolRegistered(protocolId, protocol);
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
}
