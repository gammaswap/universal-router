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

    function addProtocol(address protocol) external virtual override onlyOwner {
        require(protocol != address(0), "UniversalRouter: ZERO_ADDRESS");
        uint16 protocolId = IProtocolRoute(protocol).protocolId();
        require(protocolId > 0, "UniversalRouter: INVALID_PROTOCOL_ID");
        require(protocols[protocolId] == address(0), "UniversalRouter: PROTOCOL_ID_USED");
        protocols[protocolId] = protocol;
        emit ProtocolRegistered(protocolId, protocol);
    }

    function removeProtocol(uint16 protocolId) external virtual override onlyOwner {
        require(protocolId > 0, "UniversalRouter: INVALID_PROTOCOL_ID");
        require(protocols[protocolId] != address(0), "UniversalRouter: PROTOCOL_ID_UNUSED");
        address protocol = protocols[protocolId];
        protocols[protocolId] = address(0);
        emit ProtocolUnregistered(protocolId, protocol);
    }

    // **** SWAP (supports fee-on-transfer tokens) ****
    function _swap(uint256 amountIn, uint256 amountOutMin, Route[] memory routes) internal virtual {
        require(amountIn > 0, "UniversalRouter: ZERO_AMOUNT_IN");
        GammaSwapLibrary.safeTransferFrom(routes[0].from, msg.sender, routes[0].origin, amountIn);
        uint256 lastRoute = routes.length - 1;
        address to = routes[lastRoute].destination;
        uint256 balanceBefore = IERC20(routes[lastRoute].to).balanceOf(to);
        for (uint256 i; i <= lastRoute; i++) {
            IProtocolRoute(routes[i].hop).swap(routes[i].from, routes[i].to, routes[i].fee, routes[i].destination);
        }
        require(
            IERC20(routes[lastRoute].to).balanceOf(to) - balanceBefore >= amountOutMin,
            'UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactETHForTokens(uint256 amountOutMin, bytes calldata path, address to, uint256 deadline)
        public override virtual payable ensure(deadline) {
        Route[] memory routes = calcRoutes(path, to);
        require(routes[0].from == WETH, "UniversalRouter: AMOUNT_IN_NOT_ETH");
        uint256 amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();
        _swap(amountIn, amountOutMin, routes);
    }

    /// @dev this is the main function we'll use to swap
    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, bytes calldata path, address to, uint256 deadline)
        public override virtual ensure(deadline) {
        Route[] memory routes = calcRoutes(path, address(this));
        require(routes[routes.length - 1].to == WETH, "UniversalRouter: AMOUNT_OUT_NOT_ETH");
        _swap(amountIn, amountOutMin, routes);
        unwrapWETH(0, to);
    }

    /// @dev this is the main function we'll use to swap
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, bytes calldata path, address to, uint256 deadline)
        public override virtual ensure(deadline) {
        Route[] memory routes = calcRoutes(path, to);
        _swap(amountIn, amountOutMin, routes);
    }

    function quote(uint256 amountIn, bytes calldata path) public override virtual view returns(uint256 amountOut) {
        Route[] memory routes = calcRoutes(path, address(this));
        for (uint256 i; i < routes.length; i++) {
            amountIn = IProtocolRoute(routes[i].hop).quote(amountIn, routes[i].from, routes[i].to, routes[i].fee);
        }
        amountOut = amountIn;
    }

    /// @dev this supports transfer fees tokens too
    function calcRoutes(bytes memory path, address _to) public override virtual view returns (Route[] memory routes) {
        require(path.length >= 45 && (path.length - 20) % 25 == 0, "UniversalRouter: INVALID_PATH");
        routes = new Route[](path.numPools());
        uint256 i = 0;
        while (true) {
            bool hasMultiplePools = path.hasMultiplePools();

            routes[i] = Route({
                pair: address(0),
                from: address(0),
                to: address(0),
                protocolId: 0,
                fee: 0,
                destination: _to,
                origin: address(0),
                hop: address(0)
            });

            // only the first pool in the path is necessary
            (routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee) = path.getFirstPool().decodeFirstPool();

            routes[i].hop = protocols[routes[i].protocolId];
            require(routes[i].hop != address(0), "UniversalRouter: PROTOCOL_NOT_SET");

            (routes[i].pair, routes[i].origin) = IProtocolRoute(routes[i].hop).getOrigin(routes[i].from,
                routes[i].to, routes[i].fee);

            if(i > 0) routes[i - 1].destination = routes[i].origin;

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
        require(routes[i].destination == _to);
    }

    function getAmountsOut(uint256 amountIn, bytes memory path) public override virtual returns (uint256[] memory amounts, Route[] memory routes) {
        require(path.length >= 45 && (path.length - 20) % 25 == 0, "UniversalRouter: INVALID_PATH");
        routes = new Route[](path.numPools());
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
                destination: address(0),
                origin: address(0),
                hop: address(0)
            });

            // only the first pool in the path is necessary
            (routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee) = path.getFirstPool().decodeFirstPool();

            routes[i].hop = protocols[routes[i].protocolId];
            require(routes[i].hop != address(0), "UniversalRouter: PROTOCOL_NOT_SET");

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
        require(path.length >= 45 && (path.length - 20) % 25 == 0, "UniversalRouter: INVALID_PATH");
        routes = new Route[](path.numPools());
        amounts = new uint256[](path.numPools() + 1);
        uint256 i = routes.length - 1;
        amounts[i + 1] = amountOut;
        while (true) {
            bool hasMultiplePools = path.hasMultiplePools();

            routes[i] = Route({
                pair: address(0),
                from: address(0),
                to: address(0),
                protocolId: 0,
                fee: 0,
                destination: address(0),
                origin: address(0),
                hop: address(0)
            });

            // only the first pool in the path is necessary
            (routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee) = path.getLastPool().decodeFirstPool();

            routes[i].hop = protocols[routes[i].protocolId];
            require(routes[i].hop != address(0), "UniversalRouter: ROUTE_NOT_SET");

            (amounts[i], routes[i].pair, routes[i].fee) = IProtocolRoute(routes[i].hop).getAmountIn(amounts[i + 1],
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
