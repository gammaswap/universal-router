// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol';
import '@gammaswap/v1-core/contracts/interfaces/periphery/IExternalCallee.sol';
import '@gammaswap/v1-periphery/contracts/base/Transfers.sol';
import '@openzeppelin/contracts/access/Ownable2Step.sol';
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import './interfaces/IProtocolRoute.sol';
import './interfaces/IRouterExternalCallee.sol';
import './interfaces/IUniversalRouter.sol';
import './libraries/BytesLib2.sol';
import './libraries/Path2.sol';

/// @title Universal Router contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Swaps tokens across multiple protocols
/// @dev Protocols are supported as different routes by inheriting IProtocolRoute
contract UniversalRouter is IUniversalRouter, IRouterExternalCallee, Initializable, UUPSUpgradeable, Transfers, Ownable2Step {

    using Path2 for bytes;
    using BytesLib2 for bytes;

    /// @inheritdoc IUniversalRouter
    mapping(uint16 => address) public override protocolRoutes;

    /// @inheritdoc IUniversalRouter
    mapping(address => uint256) public override trackedPairs;

    /// @dev Initialize `WETH` address to Wrapped Ethereum contract
    constructor(address _WETH) Transfers(_WETH) {
    }

    /// @dev Initialize UniversalRouter when used as a proxy contract
    function initialize() public virtual override initializer {
        require(owner() == address(0), "UniversalRouter: INITIALIZED");
        _transferOwnership(msg.sender);
    }

    /// @dev Check current timestamp is not past blockchain's timestamp
    /// @param deadline - timestamp of transaction in seconds
    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'UniversalRouter: EXPIRED');
        _;
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
    /// @return amountOut - amount bought of final token in path
    function _swap(uint256 amountIn, uint256 amountOutMin, Route[] memory routes, address sender) internal virtual returns(uint256 amountOut){
        require(amountIn > 0, 'UniversalRouter: ZERO_AMOUNT_IN');
        send(routes[0].from, sender, routes[0].origin, amountIn);
        uint256 lastRoute = routes.length - 1;
        address to = routes[lastRoute].destination;
        uint256 balanceBefore = IERC20(routes[lastRoute].to).balanceOf(to);
        for (uint256 i; i <= lastRoute; i++) {
            IProtocolRoute(routes[i].hop).swap(routes[i].from, routes[i].to, routes[i].fee, routes[i].destination);
        }
        amountOut = IERC20(routes[lastRoute].to).balanceOf(to) - balanceBefore;
        require(amountOut >= amountOutMin, 'UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
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

    /// @inheritdoc IUniversalRouter
    function trackPair(address token0, address token1, uint24 fee, uint16 protocolId) external virtual override onlyOwner {
        address pair;
        address factory;
        (pair, token0, token1, factory) = getPairInfo(token0, token1, fee, protocolId);

        trackedPairs[pair] = block.timestamp;

        emit TrackPair(pair, token0, token1, fee, factory, protocolId);
    }

    /// @inheritdoc IUniversalRouter
    function unTrackPair(address token0, address token1, uint24 fee, uint16 protocolId) external virtual override onlyOwner {
        address pair;
        address factory;
        (pair, token0, token1, factory) = getPairInfo(token0, token1, fee, protocolId);

        trackedPairs[pair] = 0;

        emit UnTrackPair(pair, token0, token1, fee, factory, protocolId);
    }

    /// @inheritdoc IUniversalRouter
    function getPairInfo(address tokenA, address tokenB, uint24 fee, uint16 protocolId) public virtual override view returns(address pair, address token0, address token1, address factory) {
        require(tokenA != address(0), 'UniversalRouter: ZERO_ADDRESS');
        require(tokenB != address(0), 'UniversalRouter: ZERO_ADDRESS');

        address protocol = protocolRoutes[protocolId];
        require(protocol != address(0), 'UniversalRouter: ROUTE_NOT_SET_UP');

        (pair, token0, token1) = IProtocolRoute(protocol).pairFor(tokenA, tokenB, fee);

        factory = IProtocolRoute(protocol).factory();
    }

    /// @inheritdoc IExternalCallee
    function externalCall(address sender, uint128[] calldata amounts, uint256 lpTokens, bytes calldata _data) external override {
        require(lpTokens == 0, "ExternalCall: Invalid deposit");

        ExternalCallData memory data = abi.decode(_data, (ExternalCallData));

        require(data.deadline >= block.timestamp, 'ExternalCall: EXPIRED');

        Route[] memory routes = calcRoutes(data.path, address(this));

        address tokenIn = routes[0].from;
        address tokenOut = routes[routes.length - 1].to;

        uint256 balanceIn = IERC20(tokenIn).balanceOf(address(this));
        uint256 balanceOut = IERC20(tokenOut).balanceOf(address(this));

        require((balanceIn >= amounts[0] && balanceOut >= amounts[1]) || (balanceIn >= amounts[1] && balanceOut >= amounts[0]), "ExternalCall: Invalid token amounts");
        require(data.amountIn > 0 && balanceIn >= data.amountIn, "ExternalCall: Insufficient amountIn"); // only sells

        address caller = msg.sender;

        uint256 amountOut = _swap(data.amountIn, data.minAmountOut, routes, address(this));

        balanceIn = IERC20(tokenIn).balanceOf(address(this));
        balanceOut = IERC20(tokenOut).balanceOf(address(this));

        if (balanceIn > 0) GammaSwapLibrary.safeTransfer(tokenIn, caller, balanceIn);
        if (balanceOut > 0) GammaSwapLibrary.safeTransfer(tokenOut, caller, balanceOut);

        emit ExternalCallSwap(sender, caller, data.tokenId, tokenIn, tokenOut, data.amountIn, amountOut);
    }

    /// @inheritdoc Transfers
    function getGammaPoolAddress(address, uint16) internal override virtual view returns(address) {
        return address(0);
    }

    /// @inheritdoc ISendTokensCallback
    function sendTokensCallback(address[] calldata tokens, uint256[] calldata amounts, address payee, bytes calldata data) external virtual override {
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
