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

    error Expired();
    error InvalidProtocolRouteID();
    error RouterInitialized();
    error UsedProtocolRouteID();
    error UnusedProtocolRouteID();

    /// @inheritdoc IUniversalRouter
    mapping(uint16 => address) public override protocolRoutes;

    /// @inheritdoc IUniversalRouter
    mapping(address => uint256) public override trackedPairs;

    /// @dev Initialize `WETH` address to Wrapped Ethereum contract
    constructor(address _WETH) Transfers(_WETH) {
    }

    /// @dev Initialize UniversalRouter when used as a proxy contract
    function initialize() public virtual override initializer {
        if(owner() != address(0)) revert RouterInitialized();
        _transferOwnership(msg.sender);
    }

    /// @dev Check current timestamp is not past blockchain's timestamp
    /// @param deadline - timestamp of transaction in seconds
    modifier ensure(uint256 deadline) {
        if(deadline < block.timestamp) revert Expired();
        _;
    }

    /// @inheritdoc IUniversalRouter
    function addProtocolRoute(address protocol) external virtual override onlyOwner {
        _validateNonZeroAddress(protocol);
        uint16 protocolId = IProtocolRoute(protocol).protocolId();
        _validateProtocolId(protocolId);
        if(protocolRoutes[protocolId] != address(0)) revert UsedProtocolRouteID();
        protocolRoutes[protocolId] = protocol;
        emit AddProtocolRoute(protocolId, protocol);
    }

    /// @inheritdoc IUniversalRouter
    function removeProtocolRoute(uint16 protocolId) external virtual override onlyOwner {
        _validateProtocolId(protocolId);
        if(protocolRoutes[protocolId] == address(0)) revert UnusedProtocolRouteID();
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
        Route memory first = routes[0];
        send(first.from, sender, first.origin, amountIn);
        Route memory last = routes[routes.length - 1];
        uint256 balanceBefore = IERC20(last.to).balanceOf(last.destination);
        for (uint256 i; i < routes.length;) {
            Route memory route = routes[i];
            IProtocolRoute(route.hop).swap(route.from, route.to, route.fee, route.destination);
            unchecked {
                ++i;
            }
        }
        amountOut = IERC20(last.to).balanceOf(last.destination) - balanceBefore;
        _validateAmountOut(amountOut, amountOutMin);
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
    function swapExactTokensForTokensSplit(uint256 amountIn, uint256 amountOutMin, bytes[] calldata paths, uint256[] calldata weights, address to, uint256 deadline)
        external override virtual {
    }

    /// @inheritdoc IUniversalRouter
    function swapExactTokensForETHSplit(uint256 amountIn, uint256 amountOutMin, bytes[] calldata paths, uint256[] calldata weights, address to, uint256 deadline)
        external override virtual {
    }

    /// @inheritdoc IUniversalRouter
    function swapExactETHForTokensSplit(uint256 amountOutMin, bytes[] calldata paths, uint256[] calldata weights, address to, uint256 deadline)
        external override virtual payable {
    }

    // **** Estimate swap results functions ****
    /// @inheritdoc IUniversalRouter
    function quote(uint256 amountIn, bytes calldata path) public override virtual view returns(uint256 amountOut) {
        Route[] memory routes = calcRoutes(path, address(this));
        uint256 len = routes.length;
        for (uint256 i; i < len;) {
            Route memory route = routes[i];
            amountIn = IProtocolRoute(route.hop).quote(amountIn, route.from, route.to, route.fee);
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
        uint256 len = routes.length;
        for (uint256 i; i < len;) {
            Route memory route = routes[i];
            uint256 fee = IProtocolRoute(route.hop).getFee(route.from, route.to, route.fee);
            pathFee = pathFee * (1e6 - fee) / 1e6;
            unchecked {
                ++i;
            }
        }
        pathFee = 1e6 - pathFee;
    }

    /// @inheritdoc IUniversalRouter
    function quoteSplit(uint256 amountIn, bytes[] calldata paths, uint256[] memory weights) external override virtual view returns(uint256 amountOut) {
    }

    /// @inheritdoc IUniversalRouter
    function calcPathFeeSplit(bytes[] calldata paths, uint256[] memory weights) external override virtual view returns(uint256 pathFee) {
    }

    /// @inheritdoc IUniversalRouter
    function calcRoutes(bytes memory path, address to) public override virtual view returns (Route[] memory routes) {
        _validatePath(path);

        uint256 len = path.numPools();
        routes = new Route[](len);

        for(uint256 i; i < len;) {
            // only the first pool in the path is necessary
            (address from, address toAddr, uint16 protocolId, uint24 fee) = path.getFirstPool().decodeFirstPool();
            address hop = protocolRoutes[protocolId];
            _validateRoute(Route(address(0), from, toAddr, protocolId, fee, to, address(0), hop));

            (address pair, address origin) = IProtocolRoute(hop).getOrigin(from, toAddr, fee);

            routes[i] = Route({
                pair: pair,
                from: from,
                to: toAddr,
                protocolId: protocolId,
                fee: fee,
                destination: to,
                origin: origin,
                hop: hop
            });

            if(i > 0) routes[i - 1].destination = origin;

            // decide whether to continue or terminate
            if (!path.hasMultiplePools()) break;
            path = path.skipToken();

            unchecked {
                ++i;
            }
        }
        require(routes[len - 1].destination == to);
    }

    /// @inheritdoc IUniversalRouter
    function getAmountsOutSplit(uint256 amountIn, bytes[] memory paths, uint256[] memory weights) public override virtual
        returns (uint256 amountOut, uint256[][] memory amountsSplit, Route[][] memory routesSplit) {
    }

    /// @inheritdoc IUniversalRouter
    function getAmountsOutSplitNoSwap(uint256 amountIn, bytes[] memory paths, uint256[] memory weights) public override
        virtual returns (uint256 amountOut, uint256[][] memory amountsSplit, Route[][] memory routesSplit) {
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

    /// @dev Not a view function to support UniswapV3 quoting
    function _getAmountsOut(uint256 amountIn, bytes memory path, bool noSwap) internal virtual returns (uint256[] memory amounts, Route[] memory routes) {
        _validatePath(path);
        uint256 poolCount = path.numPools();
        routes = new Route[](poolCount);
        amounts = new uint256[](poolCount + 1);
        amounts[0] = amountIn;
        for (uint256 i;;) {
            // only the first pool in the path is necessary
            (address from, address to, uint16 protocolId, uint24 fee) = path.getFirstPool().decodeFirstPool();
            address hop = protocolRoutes[protocolId];

            routes[i] = Route({
                pair: address(0),
                from: from,
                to: to,
                protocolId: protocolId,
                fee: fee,
                destination: address(0),
                origin: address(0),
                hop: hop
            });

            _validateRoute(routes[i]);

            (uint256 amtOut, address pair, uint24 updatedFee) = noSwap
                ? IProtocolRoute(hop).getAmountOutNoSwap(amounts[i], from, to, fee)
                : IProtocolRoute(hop).getAmountOut(amounts[i], from, to, fee);

            amounts[i + 1] = amtOut;
            routes[i].pair = pair;
            routes[i].fee = updatedFee;

            // decide whether to continue or terminate
            if (!path.hasMultiplePools()) break;
            path = path.skipToken();

            unchecked {
                ++i;
            }
        }
    }

    /// @dev Not a view function to support UniswapV3 quoting
    /// @inheritdoc IUniversalRouter
    function getAmountsInSplit(uint256 amountOut, bytes[] memory paths, uint256[] memory weights) external override
        virtual returns (uint256 amountIn, uint256[] memory inWeights, uint256[][] memory amountsSplit, Route[][] memory routesSplit) {
    }

    /// @dev Not a view function to support UniswapV3 quoting
    /// @inheritdoc IUniversalRouter
    function getAmountsIn(uint256 amountOut, bytes memory path) public override virtual returns (uint256[] memory amounts, Route[] memory routes) {
        return _getAmountsIn(amountOut, path);
    }

    /// @dev Not a view function to support UniswapV3 quoting
    function _getAmountsIn(uint256 amountOut, bytes memory path) internal virtual returns (uint256[] memory amounts, Route[] memory routes) {
        _validatePath(path);
        uint256 poolCount = path.numPools();
        routes = new Route[](poolCount);
        amounts = new uint256[](poolCount + 1);
        amounts[poolCount] = amountOut;
        for (uint256 i = poolCount; i > 0;) {
            unchecked {
                --i;
            }

            // only the first pool in the path is necessary
            (address from, address to, uint16 protocolId, uint24 fee) = path.getLastPool().decodeFirstPool();
            address hop = protocolRoutes[protocolId];

            routes[i] = Route({
                pair: address(0),
                from: from,
                to: to,
                protocolId: protocolId,
                fee: fee,
                destination: address(0),
                origin: address(0),
                hop: hop
            });

            _validateRoute(routes[i]);

            (uint256 amtIn, address pair, uint24 updatedFee) = IProtocolRoute(hop).getAmountIn(amounts[i + 1], from, to, fee);

            amounts[i] = amtIn;
            routes[i].pair = pair;
            routes[i].fee = updatedFee;

            // decide whether to continue or terminate
            if (!path.hasMultiplePools()) break;
            path = path.hopToken();
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
    function getPairInfo(address tokenA, address tokenB, uint24 fee, uint16 protocolId) public virtual override view
        returns(address pair, address token0, address token1, address factory) {
        _validateNonZeroAddress(tokenA);
        _validateNonZeroAddress(tokenB);

        address protocol = protocolRoutes[protocolId];
        require(protocol != address(0), 'UniversalRouter: ROUTE_NOT_SET_UP');

        (pair, token0, token1) = IProtocolRoute(protocol).pairFor(tokenA, tokenB, fee);

        factory = IProtocolRoute(protocol).factory();
    }

    /// @inheritdoc IExternalCallee
    function externalCall(address sender, uint128[] calldata amounts, uint256 lpTokens, bytes calldata _data) external override virtual {
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

    /// @dev Validate individual path format: addr - protocolId - fee - addr
    /// @param path - swap path to validate
    function _validatePath(bytes memory path) internal virtual view {
        path.validatePath();
    }

    /// @dev Validate route by checking if hop exists
    function _validateRoute(Route memory route) internal virtual view {
        require(route.hop != address(0), 'UniversalRouter: PROTOCOL_ROUTE_NOT_SET');
    }

    /// @dev Check address is not zero
    function _validateNonZeroAddress(address addr) internal virtual view {
        require(addr != address(0), 'UniversalRouter: ZERO_ADDRESS');
    }

    /// @dev Check protocolId used to identify protocols in routes is not zero
    function _validateProtocolId(uint16 protocolId) internal virtual view {
        if(protocolId == 0) revert InvalidProtocolRouteID();
    }

    /// @dev Used when executing swaps to check amountOut is at least above the minimum threshold amountOutMin
    /// @param amountOut - token amount received from swap
    /// @param amountOutMin - minimum amount expected to receive from swap
    function _validateAmountOut(uint256 amountOut, uint256 amountOutMin) internal virtual view {
        require(amountOut >= amountOutMin, 'UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
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
