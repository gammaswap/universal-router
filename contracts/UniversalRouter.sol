// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol';
import '@gammaswap/v1-periphery/contracts/base/Transfers.sol';
import '@openzeppelin/contracts/access/Ownable2Step.sol';
import './interfaces/IProtocolRoute.sol';
import './interfaces/IUniversalRouter.sol';
import './libraries/BytesLib2.sol';
import './libraries/Path2.sol';

/// @title Universal Router contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Swaps tokens across multiple protocols
/// @dev Protocols are supported as different routes by inheriting IProtocolRoute
contract UniversalRouter is IUniversalRouter, Transfers, Ownable2Step {

    using Path2 for bytes;
    using BytesLib2 for bytes;

    /// @dev Returns protocol route contracts by their protocolId
    mapping(uint16 => address) public override protocolRoutes;
    mapping(address => bool) public override trackedPairs;

    /// @dev Initialize `WETH` address to Wrapped Ethereum contract
    constructor(address _WETH) Transfers(_WETH) {
    }

    /// @dev Check current timestamp is not past blockchain's timestamp
    /// @param deadline - timestamp of transaction in seconds
    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'UniversalRouter: EXPIRED');
        _;
    }

    /// @inheritdoc IUniversalRouter
    function trackPair(address token0, address token1, uint24 fee, uint16 protocolId) external virtual override onlyOwner {
        require(token0 != address(0), 'UniversalRouter: ZERO_ADDRESS');
        require(token1 != address(0), 'UniversalRouter: ZERO_ADDRESS');

        address protocol = protocolRoutes[protocolId];
        require(protocol != address(0), 'UniversalRouter: ROUTE_NOT_SET_UP');

        address pair;
        (pair, token0, token1) = IProtocolRoute(protocol).pairFor(token0, token1, fee);

        require(trackedPairs[pair] == false, "UniversalRouter: ALREADY_TRACKED");
        trackedPairs[pair] = true;

        emit TrackPair(pair, token0, token1, fee);
    }

    /// @inheritdoc IUniversalRouter
    function addProtocolRoute(address protocol) external virtual override onlyOwner {
        require(protocol != address(0), 'UniversalRouter: ZERO_ADDRESS');
        uint16 protocolId = IProtocolRoute(protocol).protocolId();
        require(protocolId > 0, 'UniversalRouter: INVALID_PROTOCOL_ROUTE_ID');
        require(protocolRoutes[protocolId] == address(0), 'UniversalRouter: PROTOCOL_ROUTE_ID_USED');
        protocolRoutes[protocolId] = protocol;
        emit AddProtocolRoute(protocolId, protocol);
    }

    /// @inheritdoc IUniversalRouter
    function removeProtocolRoute(uint16 protocolId) external virtual override onlyOwner {
        require(protocolId > 0, 'UniversalRouter: INVALID_PROTOCOL_ROUTE_ID');
        require(protocolRoutes[protocolId] != address(0), 'UniversalRouter: PROTOCOL_ROUTE_ID_UNUSED');
        address protocol = protocolRoutes[protocolId];
        protocolRoutes[protocolId] = address(0);
        emit RemoveProtocolRoute(protocolId, protocol);
    }

    // **** SWAP ****
    /// @dev Main swap function used by all public swap functions
    /// @param amountIn - quantity of token at Route[0].from to swap for token at Route[n].to
    /// @param amountOutMin - minimum quantity of token at Route[n].to willing to receive or revert
    /// @param routes - array of Route structs containing instructions to swap
    /// @param sender - address funding swap
    function _swap(uint256 amountIn, uint256 amountOutMin, Route[] memory routes, address sender) internal virtual {
        require(amountIn > 0, 'UniversalRouter: ZERO_AMOUNT_IN');
        send(routes[0].from, sender, routes[0].origin, amountIn);
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

    /// @inheritdoc IUniversalRouter
    function swapExactETHForTokens(uint256 amountOutMin, bytes calldata path, address to, uint256 deadline)
        public override virtual payable ensure(deadline) {
        Route[] memory routes = calcRoutes(path, to);
        require(routes[0].from == WETH, 'UniversalRouter: AMOUNT_IN_NOT_ETH');
        _swap(msg.value, amountOutMin, routes, address(this));
    }

    /// @inheritdoc IUniversalRouter
    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, bytes calldata path, address to, uint256 deadline)
        public override virtual ensure(deadline) {
        Route[] memory routes = calcRoutes(path, address(this));
        require(routes[routes.length - 1].to == WETH, 'UniversalRouter: AMOUNT_OUT_NOT_ETH');
        _swap(amountIn, amountOutMin, routes, msg.sender);
        unwrapWETH(0, to);
    }

    /// @inheritdoc IUniversalRouter
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, bytes calldata path, address to, uint256 deadline)
        public override virtual ensure(deadline) {
        Route[] memory routes = calcRoutes(path, to);
        _swap(amountIn, amountOutMin, routes, msg.sender);
    }

    // **** Estimate swap results functions ****
    /// @inheritdoc IUniversalRouter
    function quote(uint256 amountIn, bytes calldata path) public override virtual view returns(uint256 amountOut) {
        Route[] memory routes = calcRoutes(path, address(this));
        for (uint256 i; i < routes.length; i++) {
            amountIn = IProtocolRoute(routes[i].hop).quote(amountIn, routes[i].from, routes[i].to, routes[i].fee);
        }
        amountOut = amountIn;
    }

    /// @inheritdoc IUniversalRouter
    function calcRoutes(bytes memory path, address _to) public override virtual view returns (Route[] memory routes) {
        require(path.length >= 45 && (path.length - 20) % 25 == 0, 'UniversalRouter: INVALID_PATH');
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

            routes[i].hop = protocolRoutes[routes[i].protocolId];
            require(routes[i].hop != address(0), 'UniversalRouter: PROTOCOL_ROUTE_NOT_SET');

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

    /// @dev Not a view function to support UniswapV3 quoting
    /// @inheritdoc IUniversalRouter
    function getAmountsOut(uint256 amountIn, bytes memory path) public override virtual returns (uint256[] memory amounts, Route[] memory routes) {
        require(path.length >= 45 && (path.length - 20) % 25 == 0, 'UniversalRouter: INVALID_PATH');
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

            routes[i].hop = protocolRoutes[routes[i].protocolId];
            require(routes[i].hop != address(0), 'UniversalRouter: PROTOCOL_ROUTE_NOT_SET');

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

    /// @dev Not a view function to support UniswapV3 quoting
    /// @inheritdoc IUniversalRouter
    function getAmountsIn(uint256 amountOut, bytes memory path) public override virtual returns (uint256[] memory amounts, Route[] memory routes) {
        require(path.length >= 45 && (path.length - 20) % 25 == 0, 'UniversalRouter: INVALID_PATH');
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

            routes[i].hop = protocolRoutes[routes[i].protocolId];
            require(routes[i].hop != address(0), 'UniversalRouter: PROTOCOL_ROUTE_NOT_SET');

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

    /// @inheritdoc Transfers
    function getGammaPoolAddress(address, uint16) internal override virtual view returns(address) {
        return address(0);
    }

    /// @inheritdoc ISendTokensCallback
    function sendTokensCallback(address[] calldata tokens, uint256[] calldata amounts, address payee, bytes calldata data) external virtual override {
    }
}
