// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import '@gammaswap/v1-periphery/contracts/interfaces/external/IWETH.sol';
import './interfaces/IAeroPool.sol';
import './interfaces/IAeroPoolFactory.sol';
import './libraries/PoolAddress.sol';
import './libraries/RouterLibrary.sol';
import './BaseUniV3Quoter.sol';

contract UniversalQuoter is BaseUniV3Quoter {

    using Path2 for bytes;
    using BytesLib2 for bytes;

    constructor(address _uniFactory, address _sushiFactory, address _dsFactory, address _aeroFactory, address _uniV3Factory, address _WETH)
        BaseRouter(_uniFactory, _sushiFactory, _dsFactory, _aeroFactory, _uniV3Factory, _WETH) {
    }

    function calcOutAmount(uint256 amountIn, address tokenA, address tokenB, uint16 protocolId, uint256 fee) internal returns(uint256 amountOut, address pair, uint24 _fee) {
        uint256 reserveIn;
        uint256 reserveOut;
        _fee = uint24(fee);
        if(protocolId >= 1 && protocolId <= 3) {
            _fee = 3;
            (reserveIn, reserveOut, pair) = getReserves(tokenA, tokenB, protocolId, _fee);
            if(protocolId == 3) {
                _fee = uint24(DSLib.calcPairTradingFee(amountIn, reserveIn, reserveOut, pair));
            }
            amountOut = DSLib.getAmountOut(amountIn, reserveIn, reserveOut, _fee);
        } else if(protocolId == 4 || protocolId == 5) {
            (pair,,) = pairFor(tokenA, tokenB, protocolId, _fee);
            amountOut = IAeroPool(pair).getAmountOut(amountIn, tokenA);
        } else if(protocolId == 6) {
            _fee = uint24(fee);
            (pair,,) = pairFor(tokenA, tokenB, protocolId, _fee);
            SwapCallbackData memory data = SwapCallbackData({
                path: abi.encodePacked(tokenA, protocolId, _fee, tokenB),
                payer: address(0),
                isQuote: true
            });
            (amountOut,,,) = quoteExactInputSingle2(amountIn, pair, tokenA < tokenB,
                abi.encode(data), false);
        }

        require(amountOut > 0, "ZERO_AMOUNT");
    }

    function getAmountsOut(uint256 amountIn, bytes memory path) public virtual returns (uint256[] memory amounts, Route[] memory routes) {
        require(path.length >= 45 && (path.length - 20) % 25 == 0, "INVALID_PATH");
        routes = new Route[](path.numPools() + 1);
        amounts = new uint256[](path.numPools() + 1);
        amounts[0] = amountIn;
        uint256 i = 0;
        while (true) {
            bool hasMultiplePools = path.hasMultiplePools();

            routes[i] = Route({
                pair: address(0),
                from: address(0),
                to: address(0),
                protocolId: 0,
                fee: 0,
                dest: address(0)
            });
            // only the first pool in the path is necessary
            (routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee) = path.getFirstPool().decodeFirstPool();

            (amounts[i + 1], routes[i].pair, routes[i].fee) = calcOutAmount(amounts[i], routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee);

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

    function calcInAmount(uint256 amountOut, address tokenA, address tokenB, uint16 protocolId, uint256 fee) internal returns(uint256 amountIn, address pair, uint24 swapFee) {
        uint256 reserveIn;
        uint256 reserveOut;
        if(protocolId >= 1 && protocolId <= 3) {
            (reserveIn, reserveOut, pair) = getReserves(tokenA, tokenB, protocolId, uint24(fee));
            if(protocolId == 3) {
                uint256 _fee = 3;
                amountIn;
                while(true) {
                    fee = _fee;
                    amountIn = DSLib.getAmountIn(amountOut, reserveIn, reserveOut, fee);
                    _fee = DSLib.calcPairTradingFee(amountIn, reserveIn, reserveOut, pair);
                    if(_fee == fee) break;
                }
                swapFee = uint24(fee);
            } else {
                swapFee = 30;
                amountIn = DSLib.getAmountIn(amountOut, reserveIn, reserveOut, swapFee);
            }
        } else if(protocolId == 4 || protocolId == 5) {
            (reserveIn, reserveOut, pair) = getReserves(tokenA, tokenB, protocolId, uint24(fee));
            fee = IAeroPoolFactory(aeroFactory).getFee(pair, protocolId == 5);
            if(tokenA > tokenB) {
                (reserveIn, reserveOut, tokenA, tokenB) = (reserveOut, reserveIn, tokenB, tokenA);
                amountIn = AeroLib.getAmountIn(amountOut, tokenB, tokenA , reserveIn, reserveOut,
                    10**GammaSwapLibrary.decimals(tokenA), 10**GammaSwapLibrary.decimals(tokenB), protocolId == 5, fee);
            } else {
                amountIn = AeroLib.getAmountIn(amountOut, tokenA, tokenA , reserveIn, reserveOut,
                    10**GammaSwapLibrary.decimals(tokenA), 10**GammaSwapLibrary.decimals(tokenB), protocolId == 5, fee);
            }
        } else if(protocolId == 6) {
            swapFee = uint24(fee);
            (pair,,) = pairFor(tokenA, tokenB, protocolId, swapFee);
            SwapCallbackData memory data = SwapCallbackData({
                path: abi.encodePacked(tokenA, protocolId, swapFee, tokenB),
                payer: address(0),
                isQuote: true
            });
            (amountIn,,,) = quoteExactInputSingle2(amountOut, pair, tokenB < tokenA,
                abi.encode(data), true);
        }

        require(amountIn > 0, "ZERO_AMOUNT");
    }

    // path is assumed to be reversed from the one in getAmountsOut. In original getAmountsOut it is not reversed
    function getAmountsIn(uint256 amountOut, bytes memory path) public virtual returns (uint256[] memory amounts, Route[] memory routes) {
        require(path.length >= 45 && (path.length - 20) % 25 == 0, "INVALID_PATH");
        routes = new Route[](path.numPools() + 1);
        amounts = new uint256[](path.numPools() + 1);
        uint256 i = amounts.length - 1;
        amounts[i] = amountOut;
        while (true) {
            bool hasMultiplePools = path.hasMultiplePools();

            routes[i] = Route({
                pair: address(0),
                from: address(0),
                to: address(0),
                protocolId: 0,
                fee: 0,
                dest: address(0)
            });

            // only the first pool in the path is necessary
            (routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee) = path.getLastPool().decodeFirstPool();

            (amounts[i - 1], routes[i].pair, routes[i].fee) = calcInAmount(amounts[i], routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee);

            // decide whether to continue or terminate
            if (hasMultiplePools) {
                path = path.hopToken();
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