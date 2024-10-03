// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import './libraries/Path2.sol';
import './libraries/BytesLib2.sol';
import './libraries/RouterLibrary.sol';
import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapPair.sol";

import "forge-std/console.sol";

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

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash for UniswapV2
            )))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB, address pair) {
        (address token0,) = sortTokens(tokenA, tokenB);
        pair = pairFor(factory, tokenA, tokenB);
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

    function getAmountsOut(uint256 amountIn, bytes memory path) public view virtual returns (uint256[] memory amounts) {
        require(path.length >= 45 && (path.length - 20) % 25 == 0, "INVALID_PATH");
        //console.log("path:",path.length);
        amounts = new uint256[](path.numPools() + 1);
        //console.log("amounts.len:",amounts.length);
        amounts[0] = amountIn;
        uint256 i = 0;
        while (true) {
            bool hasMultiplePools = path.hasMultiplePools();

            bytes memory poolObj = path.getFirstPool(); // only the first pool in the path is necessary

            (address tokenA, address tokenB, uint16 protocolId, uint24 fee) = poolObj.decodeFirstPool();

            /*console.log("tokenA:",tokenA);
            console.log("tokenB:",tokenB);
            console.log("protocolId:",protocolId);
            console.log("fee:",fee);/**/

            (uint256 reserveIn, uint256 reserveOut, address pair) = getReserves(factory, tokenA, tokenB);
            /*console.log("reserveIn:",reserveIn);
            console.log("reserveOut:",reserveOut);
            console.log("pair:",pair);/**/
            //uint256 fee = calcPairTradingFee(amounts[i], reserveIn, reserveOut, pair);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut, fee);

            //console.log("amountOut:",amounts[i+1]);
            // decide whether to continue or terminate
            if (hasMultiplePools) {
                path = path.skipToken();
            } else {
                //amountOut = params.amountIn;
                break;
            }
            unchecked {
                ++i;
            }
        }
        /*for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut, address pair) = getReserves(factory, path[i], path[i + 1]);
            uint256 fee = calcPairTradingFee(amounts[i], reserveIn, reserveOut, pair);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut, fee);
        }/**/
    }
}
