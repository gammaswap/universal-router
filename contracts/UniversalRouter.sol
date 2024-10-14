// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol";
import "./interfaces/IUniversalRouter.sol";
import './BaseRouter.sol';

contract UniversalRouter is IUniversalRouter, BaseRouter, Ownable2Step {

    using Path2 for bytes;
    using BytesLib2 for bytes;

    mapping(uint16 => address) public override protocols;

    constructor(address _WETH) BaseRouter(_WETH) {
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'UniversalRouter: EXPIRED');
        _;
    }

    function addProtocol(uint16 protocolId, address protocol) external virtual override {
        require(protocolId > 0, "INVALID_PROTOCOL_ID");
        require(protocolId == IProtocolRoute(protocol).protocolId(), "PROTOCOL_ID_MATCH");
        protocols[protocolId] = protocol;
        emit ProtocolRegistered(protocolId, protocol);
    }

    // **** SWAP (supports fee-on-transfer tokens) ****
    function _swap(uint256 amountIn, uint256 amountOutMin, Route[] memory routes) internal virtual {
        GammaSwapLibrary.safeTransferFrom(routes[0].from, msg.sender, routes[0].dest, amountIn);
        uint256 lastRoute = routes.length - 1;
        address to = routes[lastRoute].dest;
        uint256 balanceBefore = IERC20(routes[lastRoute].to).balanceOf(to);
        for (uint256 i; i < lastRoute; i++) {
            IProtocolRoute(routes[i].hop).swap(routes[i].from, routes[i].to, routes[i].fee, routes[i].dest);
        }
        require(
            IERC20(routes[lastRoute].to).balanceOf(to) - balanceBefore >= amountOutMin,
            'UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactETHForTokens(uint256 amountOutMin, bytes calldata path, address to, uint256 deadline)
        public override virtual payable ensure(deadline) {
        uint256 amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        Route[] memory routes = calcRoutes(amountIn, path, to);
        require(routes[0].from == WETH, "AMOUNT_IN_NOT_ETH");
        _swap(amountIn, amountOutMin, routes);
    }

    /// @dev this is the main function we'll use to swap
    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, bytes calldata path, address to, uint256 deadline)
        public override virtual ensure(deadline) {
        Route[] memory routes = calcRoutes(amountIn, path, address(this));
        require(routes[routes.length - 1].to == WETH, "AMOUNT_OUT_NOT_ETH");
        _swap(amountIn, amountOutMin, routes);
        unwrapWETH(0, to);
    }

    /// @dev this is the main function we'll use to swap
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, bytes calldata path, address to, uint256 deadline)
        public override virtual  ensure(deadline) {
        Route[] memory routes = calcRoutes(amountIn, path, to);
        _swap(amountIn, amountOutMin, routes);
    }

    /// @dev this supports transfer fees tokens too
    function calcRoutes(uint256 amountIn, bytes memory path, address _to) public override virtual view returns (Route[] memory routes) {
        require(amountIn > 0, "ZERO_AMOUNT_IN");
        require(path.length >= 45 && (path.length - 20) % 25 == 0, "INVALID_PATH");
        routes = new Route[](path.numPools() + 1);
        uint256 i = 0;
        while (true) {
            bool hasMultiplePools = path.hasMultiplePools();

            routes[i] = Route({
                pair: address(0),
                from: address(0),
                to: address(0),
                protocolId: 0,
                fee: 0,
                dest: _to,
                hop: address(0)
            });

            // only the first pool in the path is necessary
            (routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee) = path.getFirstPool().decodeFirstPool();

            routes[i].hop = protocols[routes[i].protocolId];
            require(routes[i].hop != address(0), "PROTOCOL_NOT_SET");

            address dest;
            (routes[i].pair, dest) = IProtocolRoute(routes[i].hop).getDestination(routes[i].from,
                routes[i].to, routes[i].fee);

            if(i > 0) routes[i - 1].dest = dest;

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
        require(routes[i].dest == _to);
    }

    function getAmountsOut(uint256 amountIn, bytes memory path) public override virtual returns (uint256[] memory amounts, Route[] memory routes) {
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

    function getAmountsIn(uint256 amountOut, bytes memory path) public override virtual returns (uint256[] memory amounts, Route[] memory routes) {
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
