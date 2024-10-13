// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapPair.sol";
import "@gammaswap/v1-implementations/contracts/interfaces/external/cpmm/ICPMM.sol";

import './libraries/DSLib.sol';
import './libraries/AeroLib.sol';
import './libraries/BytesLib2.sol';
import './libraries/Path2.sol';
import './interfaces/IProtocolRoute.sol';

abstract contract BaseRouter {

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

    address public immutable uniFactory;
    address public immutable sushiFactory;
    address public immutable dsFactory;
    address public immutable aeroFactory;
    address public immutable uniV3Factory;

    address public immutable WETH;

    mapping(uint16 => address) public protocols;

    constructor(address _uniFactory, address _sushiFactory, address _dsFactory, address _aeroFactory, address _uniV3Factory, address _WETH) {
        uniFactory = _uniFactory;
        sushiFactory = _sushiFactory;
        dsFactory = _dsFactory;
        aeroFactory = _aeroFactory;
        uniV3Factory = _uniV3Factory;
        WETH = _WETH;
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
}
