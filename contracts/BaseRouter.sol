// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapPair.sol";
import "@gammaswap/v1-implementations/contracts/interfaces/external/cpmm/ICPMM.sol";
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';

import './libraries/DSLib.sol';
import './libraries/AeroLib.sol';
import './libraries/BytesLib2.sol';
import './libraries/Path2.sol';

abstract contract BaseRouter is IUniswapV3SwapCallback {

    using BytesLib2 for bytes;
    using Path2 for bytes;

    struct SwapCallbackData {
        bytes path;
        address payer;
        bool isQuote;
    }

    struct Route {
        address pair;
        address from;
        address to;
        uint16 protocolId;
        uint24 fee;
        address dest;
    }

    address public immutable uniFactory;
    address public immutable sushiFactory;
    address public immutable dsFactory;
    address public immutable aeroFactory;
    address public immutable uniV3Factory;

    address public immutable WETH;

    constructor(address _uniFactory, address _sushiFactory, address _dsFactory, address _aeroFactory, address _uniV3Factory, address _WETH) {
        uniFactory = _uniFactory;
        sushiFactory = _sushiFactory;
        dsFactory = _dsFactory;
        aeroFactory = _aeroFactory;
        uniV3Factory = _uniV3Factory;
        WETH = _WETH;
    }

    function _getTokenOut(bytes memory path) public view returns(address tokenOut) {
        bytes memory _path = path;
        while (_path.hasMultiplePools()) {
            _path = _path.skipToken();
        }
        tokenOut = _path.skipToken().toAddress(0);
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'DeltaSwapLibrary: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'DeltaSwapLibrary: ZERO_ADDRESS');
    }

    function getInitCodeHash(uint16 protocolId) internal pure returns(bytes memory) {
        if(protocolId == 1) { // UniswapV2
            return hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f';
        } else if(protocolId == 2) { // SushiswapV2
            return hex'e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303';
        } else if(protocolId == 3) { // DeltaSwap
            return hex'a82767a5e39a2e216962a2ebff796dcc37cd05dfd6f7a149e1f8fbb6bf487658';
        } else if(protocolId == 4) { // Aerodrome Non Stable
            // TODO: need the hashcode, it's the IPoolFactory(aeroFactory).implementation() in Aerodrome's github
            return hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f';
        } else if(protocolId == 5) { // Aerodrome Stable
            // TODO: need the hashcode, it's the IPoolFactory(aeroFactory).implementation() in Aerodrome's github
            return hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f';
        } else if(protocolId == 6) { // UniswapV3
            return hex'e34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54';
        }
        return hex'00';
    }

    function getSalt(address token0, address token1, uint16 protocolId, uint24 fee) internal pure returns(bytes32) {
        if(protocolId >= 1 && protocolId <= 3) {
            return keccak256(abi.encodePacked(token0, token1));
        } else if(protocolId == 4) {
            return keccak256(abi.encodePacked(token0, token1, false));
        } else if(protocolId == 5) {
            return keccak256(abi.encodePacked(token0, token1, true));
        } else if(protocolId == 6) {
            return keccak256(abi.encodePacked(token0, token1, fee));
        }
        return hex'00';
    }

    function getFactory(uint16 protocolId) internal view returns(address) {
        if(protocolId == 1) {
            return uniFactory;
        } else if(protocolId == 2) {
            return sushiFactory;
        } else if(protocolId == 3) {
            return dsFactory;
        } else if(protocolId == 4) {
            return aeroFactory;
        } else if(protocolId == 5) {
            return uniV3Factory;
        }
        return address(0);
    }

    function getPair(address tokenA, address tokenB, uint16 protocolId, uint24 fee) internal view returns(address pair) {
        (pair,,) = pairFor(tokenA, tokenB, protocolId, fee);
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address tokenA, address tokenB, uint16 protocolId, uint24 fee) internal view returns (address pair, address token0, address token1) {
        (token0, token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
                hex'ff',
                getFactory(protocolId),
                getSalt(token0, token1, protocolId, fee),
                getInitCodeHash(protocolId) // init code hash for V2 type protocols
            )))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address tokenA, address tokenB, uint16 protocolId, uint24 fee) internal view returns (uint256 reserveA, uint256 reserveB, address pair) {
        address token0;
        (pair, token0,) = pairFor(tokenA, tokenB, protocolId, fee);
        (uint256 reserve0, uint256 reserve1,) = IDeltaSwapPair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        require(amountA > 0, 'DeltaSwapLibrary: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'DeltaSwapLibrary: INSUFFICIENT_LIQUIDITY');
        amountB = amountA * reserveB / reserveA;
    }
}
