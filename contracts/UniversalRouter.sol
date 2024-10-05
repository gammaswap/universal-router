// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import './libraries/Path2.sol';
import './libraries/BytesLib2.sol';
import './libraries/RouterLibrary.sol';
import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapPair.sol";
import "@gammaswap/v1-deltaswap/contracts/libraries/DSMath.sol";

contract UniversalRouter {

    using Path2 for bytes;
    using BytesLib2 for bytes;

    address public immutable factory;

    constructor(address _factory){
        factory = _factory;
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
            // TODO: need the hashcode, it's the IPoolFactory(factory).implementation() in Aerodrome's github
            return hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f';
        }
        return hex'00';
    }

    function getSalt(address token0, address token1, uint16 protocolId) internal pure returns(bytes32) {
        if(protocolId >= 1 && protocolId <= 3) {
            return keccak256(abi.encodePacked(token0, token1));
        } else if(protocolId == 4) {
            return keccak256(abi.encodePacked(token0, token1, false));
        }
        return hex'00';
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB, uint16 protocolId) internal pure returns (address pair, address token0, address token1) {
        (token0, token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            factory,
            getSalt(token0, token1, protocolId),
            getInitCodeHash(protocolId) // init code hash for V2 type protocols
        )))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB, uint16 protocolId) internal view returns (uint256 reserveA, uint256 reserveB, address pair) {
        address token0;
        (pair, token0,) = pairFor(factory, tokenA, tokenB, protocolId);
        (uint256 reserve0, uint256 reserve1,) = IDeltaSwapPair(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        require(amountA > 0, 'DeltaSwapLibrary: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'DeltaSwapLibrary: INSUFFICIENT_LIQUIDITY');
        amountB = amountA * reserveB / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, uint256 fee) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'DeltaSwapLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'DeltaSwapLibrary: INSUFFICIENT_LIQUIDITY');
        uint256 amountInWithFee = amountIn * (1000 - fee);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint256 fee) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, 'DeltaSwapLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'DeltaSwapLibrary: INSUFFICIENT_LIQUIDITY');
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * (1000 - fee);
        amountIn = (numerator / denominator) + 1;
    }

    function calcPairTradingFee(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, address pair) internal view returns(uint256 fee) {
        uint256 tradeLiquidity = DSMath.calcTradeLiquidity(amountIn, 0, reserveIn, reserveOut);
        fee = IDeltaSwapPair(pair).estimateTradingFee(tradeLiquidity);
    }

    function calcOutAmount(uint256 amountIn, address factory, address tokenA, address tokenB, uint16 protocolId, uint256 fee) internal view returns(uint256 amountOut) {
        uint256 reserveIn;
        uint256 reserveOut;
        address pair;
        if(protocolId >= 1 && protocolId <= 3) {
            fee = 3;
            (reserveIn, reserveOut, pair) = getReserves(factory, tokenA, tokenB, protocolId);
            if(protocolId == 3) {
                fee = calcPairTradingFee(amountIn, reserveIn, reserveOut, pair);
            }
        }
        amountOut = getAmountOut(amountIn, reserveIn, reserveOut, fee);

        require(amountOut > 0, "ZERO_AMOUNT");
    }

    function getAmountsOut(uint256 amountIn, bytes memory path) public view virtual returns (uint256[] memory amounts) {
        require(path.length >= 45 && (path.length - 20) % 25 == 0, "INVALID_PATH");
        amounts = new uint256[](path.numPools() + 1);
        amounts[0] = amountIn;
        uint256 i = 0;
        while (true) {
            bool hasMultiplePools = path.hasMultiplePools();

            // only the first pool in the path is necessary
            (address tokenA, address tokenB, uint16 protocolId, uint24 fee) = path.getFirstPool().decodeFirstPool();

            amounts[i + 1] = calcOutAmount(amounts[i], factory, tokenA, tokenB, protocolId, fee);

            // decide whether to continue or terminate
            if (hasMultiplePools) {
                path = path.skipToken();
            } else {
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    function calcInAmount(uint256 amountOut, address factory, address tokenA, address tokenB, uint16 protocolId, uint256 fee) internal view returns(uint256 amountIn) {
        uint256 reserveIn;
        uint256 reserveOut;
        address pair;
        if(protocolId >= 1 && protocolId <= 3) {
            (reserveIn, reserveOut, pair) = getReserves(factory, tokenA, tokenB, protocolId);
            if(protocolId == 3) {
                uint256 _fee = 3;
                amountIn;
                while(true) {
                    fee = _fee;
                    amountIn = getAmountIn(amountOut, reserveIn, reserveOut, fee);
                    _fee = calcPairTradingFee(amountIn, reserveIn, reserveOut, pair);
                    if(_fee == fee) break;
                }
            } else {
                fee = 3;
                amountIn = getAmountIn(amountOut, reserveIn, reserveOut, fee);
            }
        }

        require(amountIn > 0, "ZERO_AMOUNT");
    }

    // path is assumed to be reversed from the one in getAmountsOut. In original getAmountsOut it is not reversed
    function getAmountsIn(uint256 amountIn, bytes memory path) public view virtual returns (uint256[] memory amounts) {
        require(path.length >= 45 && (path.length - 20) % 25 == 0, "INVALID_PATH");
        amounts = new uint256[](path.numPools() + 1);
        uint256 i = amounts.length - 1;
        amounts[i] = amountIn;
        while (true) {
            bool hasMultiplePools = path.hasMultiplePools();

            // only the first pool in the path is necessary
            (address tokenA, address tokenB, uint16 protocolId, uint24 fee) = path.getFirstPool().decodeFirstPool();

            amounts[i - 1] = calcInAmount(amounts[i], factory, tokenA, tokenB, protocolId, fee);

            // decide whether to continue or terminate
            if (hasMultiplePools) {
                path = path.skipToken();
            } else {
                break;
            }
            unchecked {
                --i;
            }
        }
    }
}
/*
console.log("tokenA:",tokenA);
console.log("tokenB:",tokenB);
console.log("protocolId:",protocolId);
console.log("fee:",fee);

console.log("reserveIn:",reserveIn);
console.log("reserveOut:",reserveOut);
console.log("pair:",pair);/**/