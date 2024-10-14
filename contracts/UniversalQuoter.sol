// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import '@gammaswap/v1-periphery/contracts/interfaces/external/IWETH.sol';
import './interfaces/IAeroPool.sol';
import './interfaces/IAeroPoolFactory.sol';
import './libraries/PoolAddress.sol';
import './libraries/RouterLibrary.sol';
import './BaseRouter.sol';

contract UniversalQuoter is BaseRouter {

    using Path2 for bytes;
    using BytesLib2 for bytes;

    constructor(address _WETH) BaseRouter(_WETH) {
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
                dest: address(0),
                hop: address(0)
            });

            // only the first pool in the path is necessary
            (routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee) = path.getFirstPool().decodeFirstPool();

            routes[i].hop = protocols[routes[i].protocolId];
            require(routes[i].hop != address(0), "PROTOCOL_NOT_SET");

            (amounts[i + 1], routes[i].pair, routes[i].fee) = IProtocolRoute(routes[i].hop).getAmountOut(amounts[i],
                routes[i].from, routes[i].to, routes[i].fee);

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
                dest: address(0),
                hop: address(0)
            });

            // only the first pool in the path is necessary
            (routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee) = path.getLastPool().decodeFirstPool();

            routes[i].hop = protocols[routes[i].protocolId];
            require(routes[i].hop != address(0), "ROUTE_NOT_SET");

            (amounts[i - 1], routes[i].pair, routes[i].fee) = IProtocolRoute(routes[i].hop).getAmountIn(amounts[i],
                routes[i].from, routes[i].to, routes[i].fee);

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