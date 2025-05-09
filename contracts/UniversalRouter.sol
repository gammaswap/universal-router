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
        for (uint256 i; i <= lastRoute;) {
            IProtocolRoute(routes[i].hop).swap(routes[i].from, routes[i].to, routes[i].fee, routes[i].destination);
            unchecked { ++i; }
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

    /// @inheritdoc IUniversalRouter
    function swapExactTokensForTokensSplit(uint256 amountIn, uint256 amountOutMin, bytes[] calldata path, uint256[] calldata weights, address to, uint256 deadline)
        public override virtual ensure(deadline) {
        _validatePathsAndWeights(path, weights, 2);
        uint256 amountOut = 0;
        uint256[] memory amountsIn = _calcSplitAmountsIn(amountIn, weights);
        for(uint256 i = 0; i < path.length;) {
            if(amountsIn[i] == 0) continue;
            Route[] memory routes = calcRoutes(path[i], to);
            amountOut += _swap(amountsIn[i], 0, routes, msg.sender);
            unchecked { ++i; }
        }
        require(amountOut >= amountOutMin, 'UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
    }

    /// @inheritdoc IUniversalRouter
    function swapExactTokensForETHSplit(uint256 amountIn, uint256 amountOutMin, bytes[] calldata path, uint256[] calldata weights, address to, uint256 deadline)
        public override virtual ensure(deadline) {
        _validatePathsAndWeights(path, weights, 1);
        uint256 amountOut = 0;
        uint256[] memory amountsIn = _calcSplitAmountsIn(amountIn, weights);
        for(uint256 i = 0; i < path.length;) {
            if(amountsIn[i] == 0) continue;
            Route[] memory routes = calcRoutes(path[i], address(this));
            amountOut += _swap(amountsIn[i], 0, routes, msg.sender);
            unwrapWETH(0, to);
            unchecked { ++i; }
        }
        require(amountOut >= amountOutMin, 'UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
    }

    /// @inheritdoc IUniversalRouter
    function swapExactETHForTokensSplit(uint256 amountOutMin, bytes[] calldata path, uint256[] calldata weights, address to, uint256 deadline)
        public override virtual payable ensure(deadline) {
        _validatePathsAndWeights(path, weights, 0);
        uint256 amountOut = 0;
        uint256[] memory amountsIn = _calcSplitAmountsIn(msg.value, weights);
        for(uint256 i = 0; i < path.length;) {
            if(amountsIn[i] == 0) continue;
            Route[] memory routes = calcRoutes(path[i], to);
            amountOut += _swap(amountsIn[i], 0, routes, msg.sender);
            unchecked { ++i; }
        }
        require(amountOut >= amountOutMin, 'UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
    }

    // **** Estimate swap results functions ****
    /// @inheritdoc IUniversalRouter
    function quote(uint256 amountIn, bytes calldata path) public override virtual view returns(uint256 amountOut) {
        Route[] memory routes = calcRoutes(path, address(this));
        for (uint256 i; i < routes.length;) {
            amountIn = IProtocolRoute(routes[i].hop).quote(amountIn, routes[i].from, routes[i].to, routes[i].fee);
            unchecked {
                ++i;
            }
        }
        amountOut = amountIn;
    }

    /// @inheritdoc IUniversalRouter
    function calcPathFee(bytes calldata path) public override view returns(uint256 pathFee) {
        Route[] memory routes = calcRoutes(path, address(this));
        pathFee = 1e6;
        for (uint256 i; i < routes.length;) {
            uint256 fee = IProtocolRoute(routes[i].hop).getFee(routes[i].from, routes[i].to, routes[i].fee);
            pathFee = pathFee * (1e6 - fee) / 1e6;
            unchecked {
                ++i;
            }
        }
        pathFee = 1e6 - pathFee;
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

    /// @dev Calculate how much of the sold token will be sold at each path using the weights array
    /// @param amountIn - quantity of token to sell
    /// @param weights - percentage of amountIn to swap in each path. Must add up to 1. If there's some left over, it will be swapped in the last path
    /// @return amountsIn - amount sold at each path
    function _calcSplitAmountsIn(uint256 amountIn, uint256[] memory weights) internal view returns (uint256[] memory amountsIn) {
        uint256 len = weights.length;
        amountsIn = new uint256[](len);
        uint256 remainder = amountIn;

        for (uint256 i = 0; i < len;) {
            uint256 w = amountIn * weights[i] / 1e18;
            uint256 alloc = w <= remainder ? w : remainder;
            amountsIn[i] = alloc;
            remainder -= alloc;
            if (remainder == 0) break;
            unchecked { ++i; }
        }

        if (remainder > 0) {
            unchecked { amountsIn[len - 1] += remainder; }
        }
    }

    /// @dev Validate the paths and weights to use in split swaps
    /// @param path - paths through which tokens will be swapped
    /// @param weights - percentage of amountIn to swap in each path. Must add up to 1. If there's some left over, it will be swapped in the last path
    /// @param swapType - 0: swap ETH for token, 1: swap token for ETH, 2: swap token for token
    function _validatePathsAndWeights(bytes[] memory path, uint256[] memory weights, uint8 swapType) internal virtual {
        require(path.length > 0, 'UniversalRouter: MISSING_PATHS');
        require(path.length == weights.length, 'UniversalRouter: INVALID_WEIGHTS');

        address tokenIn = path[0].getTokenIn();
        address tokenOut = path[0].getTokenOut();

        require(tokenIn != tokenOut, 'UniversalRouter: INVALID_PATH_TOKENS');

        if(swapType == 0) {
            require(tokenIn == WETH, 'UniversalRouter: AMOUNT_IN_NOT_ETH'); // we can check the path ends in ETH somewhere else
        } else if(swapType == 1) {
            require(tokenOut == WETH, 'UniversalRouter: AMOUNT_OUT_NOT_ETH'); // we can check the path ends in ETH somewhere else
        }

        for(uint256 i = 1; i < path.length;) {
            require(tokenIn == path[i].getTokenIn() && tokenOut == path[i].getTokenOut(), 'UniversalRouter: INVALID_PATH_TOKENS');
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IUniversalRouter
    function getAmountsOutSplit(uint256 amountIn, bytes[] memory path, uint256[] memory weights) public override virtual
        returns (uint256 amountOut, uint256[][] memory amountsSplit, Route[][] memory routesSplit) {
        return _getAmountsOutSplit(amountIn, path, weights, false);
    }

    /// @inheritdoc IUniversalRouter
    function getAmountsOutSplitNoSwap(uint256 amountIn, bytes[] memory path, uint256[] memory weights) public override
        virtual returns (uint256 amountOut, uint256[][] memory amountsSplit, Route[][] memory routesSplit) {
        return _getAmountsOutSplit(amountIn, path, weights, true);
    }

    // must check that weights add up to 1
    function _getAmountsOutSplit(uint256 amountIn, bytes[] memory path, uint256[] memory weights, bool noSwap) internal
        virtual returns (uint256 amountOut, uint256[][] memory amountsSplit, Route[][] memory routesSplit) {
        require(path.length == weights.length);
        _validatePathsAndWeights(path, weights, 2);
        amountsSplit = new uint256[][](path.length);
        routesSplit = new Route[][](path.length);
        uint256[] memory amountsIn = _calcSplitAmountsIn(amountIn, weights);
        for(uint256 i = 0; i < amountsIn.length;) {
            if(amountsIn[i] == 0) continue;
            (uint256[] memory amounts, Route[] memory routes) = _getAmountsOut(amountsIn[i], path[i], noSwap);
            for(uint256 j = 0; j < amounts.length;) {
                amountsSplit[i][j] = amounts[j];
                routesSplit[i][j] = routes[j];
                amountOut += amounts[i];
                unchecked {
                    ++j;
                }
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Not a view function to support UniswapV3 quoting
    /// @inheritdoc IUniversalRouter
    function getAmountsOutNoSwap(uint256 amountIn, bytes memory path) public override virtual returns (uint256[] memory amounts, Route[] memory routes) {
        return _getAmountsOut(amountIn, path, true);
    }

    /// @dev Not a view function to support UniswapV3 quoting
    /// @inheritdoc IUniversalRouter
    function getAmountsOut(uint256 amountIn, bytes memory path) public override virtual returns (uint256[] memory amounts, Route[] memory routes) {
        return _getAmountsOut(amountIn, path, false);
    }

    /// dev Not a view function to support UniswapV3 quoting
    /// inheritdoc IUniversalRouter
    function _getAmountsOut(uint256 amountIn, bytes memory path, bool noSwap) internal virtual returns (uint256[] memory amounts, Route[] memory routes) {
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

            if(noSwap) {
                (amounts[i + 1], routes[i].pair, routes[i].fee) = IProtocolRoute(routes[i].hop).getAmountOutNoSwap(amounts[i],
                    routes[i].from, routes[i].to, routes[i].fee);
            } else {
                (amounts[i + 1], routes[i].pair, routes[i].fee) = IProtocolRoute(routes[i].hop).getAmountOut(amounts[i],
                    routes[i].from, routes[i].to, routes[i].fee);
            }

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
