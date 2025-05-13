// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import "./UniversalRouter.sol";

/// @title Universal Router Split contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Swaps tokens across multiple protocols splitting the amounts across multiple routes
/// @dev Protocols are supported as different routes by inheriting IProtocolRoute
contract UniversalRouterSplit is UniversalRouter {

    using BytesLib2 for bytes;
    using Path2 for bytes;

    /// @dev Initialize `WETH` address to Wrapped Ethereum contract
    constructor(address _WETH) UniversalRouter(_WETH) {
    }

    function _swapSplit(uint256 amountIn, uint256 amountOutMin, bytes[] memory paths, uint256[] memory weights, address to,
        uint8 swapType, address sender) internal virtual returns (uint256 amountOut) {
        _validatePathsAndWeights(paths, weights, swapType);
        uint256[] memory amountsIn = _splitAmount(amountIn, weights);
        for(uint256 i = 0; i < paths.length;) {
            Route[] memory routes = calcRoutes(paths[i], swapType == 1 ? address(this) : to);
            amountOut += _swap(amountsIn[i], 0, routes, sender);
            if(swapType == 1) {
                unwrapWETH(0, to);
            }
            unchecked {
                ++i;
            }
        }
        _validateAmountOut(amountOut, amountOutMin);
    }

    /// @inheritdoc IUniversalRouter
    function swapExactTokensForTokensSplit(uint256 amountIn, uint256 amountOutMin, bytes[] calldata paths, uint256[] calldata weights, address to, uint256 deadline)
        public override virtual ensure(deadline) {
        _swapSplit(amountIn, amountOutMin, paths, weights, to, 2, msg.sender);
    }

    /// @inheritdoc IUniversalRouter
    function swapExactTokensForETHSplit(uint256 amountIn, uint256 amountOutMin, bytes[] calldata paths, uint256[] calldata weights, address to, uint256 deadline)
        public override virtual ensure(deadline) {
        _swapSplit(amountIn, amountOutMin, paths, weights, address(this), 1, msg.sender);
    }

    /// @inheritdoc IUniversalRouter
    function swapExactETHForTokensSplit(uint256 amountOutMin, bytes[] calldata paths, uint256[] calldata weights, address to, uint256 deadline)
        public override virtual payable ensure(deadline) {
        _swapSplit(msg.value, amountOutMin, paths, weights, to, 0, msg.sender);
    }

    /// @dev Calculate how much of the sold token will be sold at each path using the weights array
    /// @param amount - quantity of token to split
    /// @param weights - percentage of amount to swap in each path. Must add up to 1. If there's some left over, it will be swapped in the last path
    /// @return amounts - amount split at each path
    function _splitAmount(uint256 amount, uint256[] memory weights) internal view returns (uint256[] memory amounts) {
        uint256 len = weights.length;
        amounts = new uint256[](len);
        uint256 remainder = amount;

        for (uint256 i = 0; i < len;) {
            uint256 w = amount * weights[i] / 1e18;
            uint256 alloc = w <= remainder ? w : remainder;
            amounts[i] = alloc;
            remainder -= alloc;
            if (remainder == 0) break;
            unchecked {
                ++i;
            }
        }

        if (remainder > 0) {
            unchecked {
                amounts[len - 1] += remainder;
            }
        }
    }

    /// @inheritdoc IUniversalRouter
    function getAmountsOutSplit(uint256 amountIn, bytes[] memory paths, uint256[] memory weights) public override virtual
        returns (uint256 amountOut, uint256[][] memory amountsSplit, Route[][] memory routesSplit) {
        return _getAmountsOutSplit(amountIn, paths, weights, false);
    }

    /// @inheritdoc IUniversalRouter
    function getAmountsOutSplitNoSwap(uint256 amountIn, bytes[] memory paths, uint256[] memory weights) public override
        virtual returns (uint256 amountOut, uint256[][] memory amountsSplit, Route[][] memory routesSplit) {
        return _getAmountsOutSplit(amountIn, paths, weights, true);
    }

    function _getAmountsOutSplit(uint256 amountIn, bytes[] memory paths, uint256[] memory weights, bool noSwap) internal
        virtual returns (uint256 amountOut, uint256[][] memory amountsSplit, Route[][] memory routesSplit) {
        require(paths.length == weights.length);
        _validatePathsAndWeights(paths, weights, 2);
        amountsSplit = new uint256[][](paths.length);
        routesSplit = new Route[][](paths.length);
        uint256[] memory amountsIn = _splitAmount(amountIn, weights);
        for(uint256 i = 0; i < amountsIn.length;) {
            (uint256[] memory amounts, Route[] memory routes) = _getAmountsOut(amountsIn[i], paths[i], noSwap);
            amountsSplit[i] = new uint256[](amounts.length);
            routesSplit[i] = new Route[](routes.length);
            for(uint256 j = 0; j < amounts.length;) {
                amountsSplit[i][j] = amounts[j];
                if(j < routes.length) {
                    routesSplit[i][j] = routes[j];
                }
                unchecked {
                    ++j;
                }
            }
            amountOut += amounts[amounts.length - 1];
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Not a view function to support UniswapV3 quoting
    /// @inheritdoc IUniversalRouter
    function getAmountsInSplit(uint256 amountOut, bytes[] memory paths, uint256[] memory weights) public override
        virtual returns (uint256 amountIn, uint256[] memory inWeights, uint256[][] memory amountsSplit, Route[][] memory routesSplit) {
        require(paths.length == weights.length);
        _validatePathsAndWeights(paths, weights, 2);
        inWeights = new uint256[](paths.length);
        amountsSplit = new uint256[][](paths.length);
        routesSplit = new Route[][](paths.length);
        uint256[] memory amountsOut = _splitAmount(amountOut, weights);
        for(uint256 i = 0; i < amountsOut.length;) {
            (uint256[] memory amounts, Route[] memory routes) = _getAmountsIn(amountsOut[i], paths[i]);
            amountsSplit[i] = new uint256[](amounts.length);
            routesSplit[i] = new Route[](routes.length);
            for(uint256 j = 0; j < amounts.length;) {
                amountsSplit[i][j] = amounts[j];
                if(j < routes.length) {
                    routesSplit[i][j] = routes[j];
                }
                unchecked {
                    ++j;
                }
            }
            amountIn += amounts[0];
            unchecked {
                ++i;
            }
        }
        for(uint256 i = 0; i < amountsSplit.length;) {
            inWeights[i] = amountsSplit[i][0] * 1e18 / amountIn;
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IExternalCallee
    function externalCall(address sender, uint128[] calldata amounts, uint256 lpTokens, bytes calldata _data) external override virtual {
        require(lpTokens == 0, "ExternalCall: Invalid deposit");

        ExternalCallData memory data = abi.decode(_data, (ExternalCallData));

        require(data.deadline >= block.timestamp, 'ExternalCall: EXPIRED');

        _processSwap(sender, amounts, lpTokens, data, data.path.isSinglePath());
    }

    /// @dev Perform swap that is of multiple paths or single path
    /// @param sender - address that requested the flash loan
    /// @param amounts - collateral token amounts flash loaned from GammaPool
    /// @param lpTokens - quantity of CFMM LP tokens flash loaned
    /// @param data - optional bytes parameter for custom user defined data
    /// @param isSinglePath - true if path in data struct is a path of multiple paths
    function _processSwap(address sender, uint128[] memory amounts, uint256 lpTokens, ExternalCallData memory data, bool isSinglePath) internal virtual {
        address tokenIn;
        address tokenOut;

        bytes[] memory paths;
        uint256[] memory weights;

        if(isSinglePath) {
            tokenIn = data.path.getTokenIn();
            tokenOut = data.path.getTokenOut();
        } else {
            (paths, weights) = data.path.toPathsAndWeightsArray();
            tokenIn = paths[0].getTokenIn();
            tokenOut = paths[0].getTokenOut();
        }

        uint256 balanceIn = IERC20(tokenIn).balanceOf(address(this));
        uint256 balanceOut = IERC20(tokenOut).balanceOf(address(this));

        require((balanceIn >= amounts[0] && balanceOut >= amounts[1]) || (balanceIn >= amounts[1] && balanceOut >= amounts[0]), "ExternalCall: Invalid token amounts");
        require(data.amountIn > 0 && balanceIn >= data.amountIn, "ExternalCall: Insufficient amountIn"); // only sells

        address caller = msg.sender;
        uint256 amountOut;

        if(isSinglePath) {
            Route[] memory routes = calcRoutes(data.path, address(this));
            amountOut = _swap(data.amountIn, data.minAmountOut, routes, address(this));
        } else {
            amountOut = _swapSplit(data.amountIn, data.minAmountOut, paths, weights, address(this), 2, address(this));
        }

        balanceIn = IERC20(tokenIn).balanceOf(address(this));
        balanceOut = IERC20(tokenOut).balanceOf(address(this));

        if (balanceIn > 0) GammaSwapLibrary.safeTransfer(tokenIn, caller, balanceIn);
        if (balanceOut > 0) GammaSwapLibrary.safeTransfer(tokenOut, caller, balanceOut);

        emit ExternalCallSwap(sender, caller, data.tokenId, tokenIn, tokenOut, data.amountIn, amountOut);
    }

    /// @dev Validate the paths and weights to use in split swaps
    /// @param paths - paths through which tokens will be swapped
    /// @param weights - percentage of amountIn to swap in each path. Must add up to 1. If there's some left over, it will be swapped in the last path
    /// @param swapType - 0: swap ETH for token, 1: swap token for ETH, 2: swap token for token
    function _validatePathsAndWeights(bytes[] memory paths, uint256[] memory weights, uint8 swapType) internal virtual {
        require(paths.length > 0, 'UniversalRouter: MISSING_PATHS');
        require(paths.length == weights.length, 'UniversalRouter: INVALID_WEIGHTS');

        _validatePath(paths[0]);
        address tokenIn = paths[0].getTokenIn();
        address tokenOut = paths[0].getTokenOut();

        require(tokenIn != tokenOut, 'UniversalRouter: INVALID_PATH_TOKENS');

        if(swapType == 0) {
            require(tokenIn == WETH, 'UniversalRouter: AMOUNT_IN_NOT_ETH'); // we can check the path ends in ETH somewhere else
        } else if(swapType == 1) {
            require(tokenOut == WETH, 'UniversalRouter: AMOUNT_OUT_NOT_ETH'); // we can check the path ends in ETH somewhere else
        }

        uint256 totalWeights = weights[0];
        for(uint256 i = 1; i < paths.length;) {
            _validatePath(paths[i]);
            require(tokenIn == paths[i].getTokenIn() && tokenOut == paths[i].getTokenOut(), 'UniversalRouter: INVALID_PATH_TOKENS');
            unchecked {
                totalWeights += weights[i];
                ++i;
            }
        }
        require(totalWeights > 0 && totalWeights <= 1e18, 'UniversalRouter: INVALID_WEIGHTS');
    }

    /// @inheritdoc IUniversalRouter
    function swapExactETHForTokens(uint256 amountOutMin, bytes calldata path, address to, uint256 deadline) public override
        virtual payable {
    }

    /// @inheritdoc IUniversalRouter
    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, bytes calldata path, address to, uint256 deadline)
        public override virtual {
    }

    /// @inheritdoc IUniversalRouter
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, bytes calldata path, address to, uint256 deadline)
        public override virtual {
    }

    /// @inheritdoc IUniversalRouter
    function trackPair(address token0, address token1, uint24 fee, uint16 protocolId) external virtual override {
    }

    /// @inheritdoc IUniversalRouter
    function unTrackPair(address token0, address token1, uint24 fee, uint16 protocolId) external virtual override {
    }
}
