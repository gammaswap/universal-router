// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import './libraries/Path2.sol';
import './libraries/BytesLib2.sol';
import './libraries/RouterLibrary.sol';
import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapPair.sol";
import "@gammaswap/v1-deltaswap/contracts/libraries/DSMath.sol";
import "@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol";
import "@gammaswap/v1-periphery/contracts/interfaces/external/IWETH.sol";

contract UniversalRouter {

    using Path2 for bytes;
    using BytesLib2 for bytes;

    address public immutable factory;
    address public immutable WETH;

    constructor(address _factory, address _WETH){
        factory = _factory;
        WETH = _WETH;
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'DeltaSwapRouter: EXPIRED');
        _;
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

    function getInitCodeHash(uint16 protocolId) internal pure returns(bytes memory) {
        if(protocolId == 1) { // UniswapV2
            return hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f';
        } else if(protocolId == 2) { // SushiswapV2
            return hex'e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303';
        } else if(protocolId == 3) { // DeltaSwap
            return hex'a82767a5e39a2e216962a2ebff796dcc37cd05dfd6f7a149e1f8fbb6bf487658';
        } else if(protocolId == 4) { // Aerodrome Non Stable
            // TODO: need the hashcode, it's the IPoolFactory(factory).implementation() in Aerodrome's github
            return hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f';
        } else if(protocolId == 5) { // Aerodrome Stable
            // TODO: need the hashcode, it's the IPoolFactory(factory).implementation() in Aerodrome's github
            return hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f';
        }
        return hex'00';
    }

    function getSalt(address token0, address token1, uint16 protocolId) internal pure returns(bytes32) {
        if(protocolId >= 1 && protocolId <= 3) {
            return keccak256(abi.encodePacked(token0, token1));
        } else if(protocolId == 4) {
            return keccak256(abi.encodePacked(token0, token1, false));
        } else if(protocolId == 5) {
            return keccak256(abi.encodePacked(token0, token1, true));
        }
        return hex'00';
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address factory, address tokenA, address tokenB, uint16 protocolId) internal pure returns (address pair, address token0, address token1) {
        (token0, token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            factory,
            getSalt(token0, token1, protocolId),
            getInitCodeHash(protocolId) // init code hash for V2 type protocols
        )))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB, uint16 protocolId) internal view returns (uint256 reserveA, uint256 reserveB, address pair) {
        address token0;
        (pair, token0,) = pairFor(factory, tokenA, tokenB, protocolId);
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

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint256 fee) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, 'DeltaSwapLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'DeltaSwapLibrary: INSUFFICIENT_LIQUIDITY');
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * (1000 - fee);
        amountIn = (numerator / denominator) + 1;
    }

    function calcPairTradingFee(uint256 amountIn, uint256 reserveIn, uint256 reserveOut, address pair) internal view returns(uint256 fee) {
        uint256 tradeLiquidity = DSMath.calcTradeLiquidity(amountIn, 0, reserveIn, reserveOut);
        fee = IDeltaSwapPair(pair).estimateTradingFee(tradeLiquidity);
    }

    function calcOutAmount(uint256 amountIn, address factory, address tokenA, address tokenB, uint16 protocolId, uint256 fee) internal view returns(uint256 amountOut, address pair, uint24 _fee) {
        uint256 reserveIn;
        uint256 reserveOut;
        _fee = uint24(fee);
        if(protocolId >= 1 && protocolId <= 3) {
            _fee = 3;
            (reserveIn, reserveOut, pair) = getReserves(factory, tokenA, tokenB, protocolId);
            if(protocolId == 3) {
                _fee = uint24(calcPairTradingFee(amountIn, reserveIn, reserveOut, pair));
            }
            amountOut = getAmountOut(amountIn, reserveIn, reserveOut, _fee);
        } else if(protocolId == 4 || protocolId == 5) {
            (pair,,) = pairFor(factory, tokenA, tokenB, protocolId);
            //amountOut = IPool(pair).getAmountOut(amountIn, tokenA); TODO: This is supposed to be the AeroDrome IPool interface
        }

        require(amountOut > 0, "ZERO_AMOUNT");
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quotePath(uint256 amountIn, bytes memory path) internal view returns (uint256 amountOut, uint256[] memory reserves) {
        require(path.length >= 45 && (path.length - 20) % 25 == 0, "INVALID_PATH");
        reserves = new uint256[](path.numPools() * 2);
        amountOut = amountIn;
        uint256 i = 0;
        while (true) {
            bool hasMultiplePools = path.hasMultiplePools();
            // only the first pool in the path is necessary
            (address tokenA, address tokenB, uint16 protocolId, uint24 fee) = path.getFirstPool().decodeFirstPool();

            (reserves[i], reserves[i + 1],) = getReserves(factory, tokenA, tokenB, protocolId);

            amountOut = quote(amountOut, reserves[i], reserves[i + 1]);

            // decide whether to continue or terminate
            if (hasMultiplePools) {
                path = path.skipToken();
            } else {
                break;
            }
            unchecked {
                i += 2;
            }
        }
    }

    struct Route {
        address pair;
        address from;
        address to;
        uint16 protocolId;
        uint24 fee;
    }

    function getAmountsOut(uint256 amountIn, bytes memory path) public view virtual returns (uint256[] memory amounts, Route[] memory routes) {
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
                fee: 0
            });
            // only the first pool in the path is necessary
            (routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee) = path.getFirstPool().decodeFirstPool();

            (amounts[i + 1], routes[i].pair, routes[i].fee) = calcOutAmount(amounts[i], factory, routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee);

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

    function calcInAmount(uint256 amountOut, address factory, address tokenA, address tokenB, uint16 protocolId, uint256 fee) internal view returns(uint256 amountIn, address pair, uint24 swapFee) {
        uint256 reserveIn;
        uint256 reserveOut;
        if(protocolId >= 1 && protocolId <= 3) {
            (reserveIn, reserveOut, pair) = getReserves(factory, tokenA, tokenB, protocolId);
            if(protocolId == 3) {
                uint256 _fee = 3;
                amountIn;
                while(true) {
                    fee = _fee;
                    amountIn = getAmountIn(amountOut, reserveIn, reserveOut, fee);
                    _fee = calcPairTradingFee(amountIn, reserveIn, reserveOut, pair);
                    if(_fee == fee) break;
                }
                swapFee = uint24(fee);
            } else {
                swapFee = 3;
                amountIn = getAmountIn(amountOut, reserveIn, reserveOut, swapFee);
            }
        } else if(protocolId == 4 || protocolId == 5) {
            // TODO: Need to get parameters for AeroDrome function call and update logic for getAmountsIn
            // We could also update logic to function for getAmountsOut to avoid making the external call
            //amountIn = getAmountOutAerodrome();
        }

        require(amountIn > 0, "ZERO_AMOUNT");
    }

    // path is assumed to be reversed from the one in getAmountsOut. In original getAmountsOut it is not reversed
    function getAmountsIn(uint256 amountOut, bytes memory path) public view virtual returns (uint256[] memory amounts, Route[] memory routes) {
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
                fee: 0
            });

            // only the first pool in the path is necessary
            //(address tokenA, address tokenB, uint16 protocolId, uint24 fee) = path.getFirstPool().decodeFirstPool();
            (routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee) = path.getLastPool().decodeFirstPool();

            //amounts[i - 1] = calcInAmount(amounts[i], factory, tokenA, tokenB, protocolId, fee);
            (amounts[i - 1], routes[i].pair, routes[i].fee) = calcInAmount(amounts[i], factory, routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee);
            //(amounts[i + 1], route[i].pair) = calcOutAmount(amounts[i], factory, route[i].from, route[i].to, route[i].protocolId, route[i].fee);

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

    function getAmountOutAerodrome(uint256 amountIn, address tokenIn, address token0, uint256 reserve0, uint256 reserve1, uint256 decimals0, uint256 decimals1, bool stable) external view returns (uint256) {
        (uint256 _reserve0, uint256 _reserve1) = (reserve0, reserve1);
        //TODO: need to add IPoolFactory interface
        //amountIn -= (amountIn * IPoolFactory(factory).getFee(address(this), stable)) / 10000; // remove fee from amount received
        if(stable) {
            return _getAmountOutStable(amountIn, tokenIn, token0, _reserve0, _reserve1, decimals0, decimals1);
        } else {
            return _getAmountOutNonStable(amountIn, tokenIn, token0, _reserve0, _reserve1);
        }
    }

    function _getAmountOutStable(
        uint256 amountIn,
        address tokenIn,
        address token0,
        uint256 _reserve0,
        uint256 _reserve1,
        uint256 decimals0,
        uint256 decimals1
    ) internal view returns (uint256) {
        uint256 xy = _k(_reserve0, _reserve1, decimals0, decimals1, true);
        _reserve0 = (_reserve0 * 1e18) / decimals0;
        _reserve1 = (_reserve1 * 1e18) / decimals1;
        (uint256 reserveA, uint256 reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
        amountIn = tokenIn == token0 ? (amountIn * 1e18) / decimals0 : (amountIn * 1e18) / decimals1;
        uint256 y = reserveB - _get_y(amountIn + reserveA, xy, reserveB, decimals0, decimals1);
        return (y * (tokenIn == token0 ? decimals1 : decimals0)) / 1e18;
    }

    function _getAmountOutNonStable(
        uint256 amountIn,
        address tokenIn,
        address token0,
        uint256 _reserve0,
        uint256 _reserve1
    ) internal view returns (uint256) {
        (uint256 reserveA, uint256 reserveB) = tokenIn == token0 ? (_reserve0, _reserve1) : (_reserve1, _reserve0);
        return (amountIn * reserveB) / (reserveA + amountIn);
    }

    function _f(uint256 x0, uint256 y) internal pure returns (uint256) {
        uint256 _a = (x0 * y) / 1e18;
        uint256 _b = ((x0 * x0) / 1e18 + (y * y) / 1e18);
        return (_a * _b) / 1e18;
    }

    function _d(uint256 x0, uint256 y) internal pure returns (uint256) {
        return (3 * x0 * ((y * y) / 1e18)) / 1e18 + ((((x0 * x0) / 1e18) * x0) / 1e18);
    }

    function _get_y(uint256 x0, uint256 xy, uint256 y, uint256 decimals0, uint256 decimals1) internal view returns (uint256) {
        for (uint256 i = 0; i < 255; i++) {
            uint256 k = _f(x0, y);
            if (k < xy) {
                // there are two cases where dy == 0
                // case 1: The y is converged and we find the correct answer
                // case 2: _d(x0, y) is too large compare to (xy - k) and the rounding error
                //         screwed us.
                //         In this case, we need to increase y by 1
                uint256 dy = ((xy - k) * 1e18) / _d(x0, y);
                if (dy == 0) {
                    if (k == xy) {
                        // We found the correct answer. Return y
                        return y;
                    }
                    if (_k(x0, y + 1, decimals0, decimals1, true) > xy) {
                        // If _k(x0, y + 1) > xy, then we are close to the correct answer.
                        // There's no closer answer than y + 1
                        return y + 1;
                    }
                    dy = 1;
                }
                y = y + dy;
            } else {
                uint256 dy = ((k - xy) * 1e18) / _d(x0, y);
                if (dy == 0) {
                    if (k == xy || _f(x0, y - 1) < xy) {
                        // Likewise, if k == xy, we found the correct answer.
                        // If _f(x0, y - 1) < xy, then we are close to the correct answer.
                        // There's no closer answer than "y"
                        // It's worth mentioning that we need to find y where f(x0, y) >= xy
                        // As a result, we can't return y - 1 even it's closer to the correct answer
                        return y;
                    }
                    dy = 1;
                }
                y = y - dy;
            }
        }
        revert("!y");
    }

    function _k(uint256 x, uint256 y, uint256 decimals0, uint256 decimals1, bool stable) internal view returns (uint256) {
        if (stable) {
            uint256 _x = (x * 1e18) / decimals0;
            uint256 _y = (y * 1e18) / decimals1;
            uint256 _a = (_x * _y) / 1e18;
            uint256 _b = ((_x * _x) / 1e18 + (_y * _y) / 1e18);
            return (_a * _b) / 1e18; // x3y+y3x >= k
        } else {
            return x * y; // xy >= k
        }
    }

    /// TODO: Must incorporate this logic in the quoting logic for AeroDrome stable pools
    function quoteStableLiquidityRatio(
        address tokenA,
        address tokenB,
        address _factory
    ) external view returns (uint256 ratio) {
        /*IPool pool = IPool(poolFor(tokenA, tokenB, true, _factory));

        uint256 decimalsA = 10 ** IERC20Metadata(tokenA).decimals();
        uint256 decimalsB = 10 ** IERC20Metadata(tokenB).decimals();

        uint256 investment = decimalsA;
        uint256 out = pool.getAmountOut(investment, tokenA);
        (uint256 amountA, uint256 amountB, ) = quoteAddLiquidity(tokenA, tokenB, true, _factory, investment, out);

        amountA = (amountA * 1e18) / decimalsA;
        amountB = (amountB * 1e18) / decimalsB;
        out = (out * 1e18) / decimalsB;
        investment = (investment * 1e18) / decimalsA;

        ratio = (((out * 1e18) / investment) * amountA) / amountB;

        return (investment * 1e18) / (ratio + 1e18);/**/
    }

    // **** SWAP ****
    function _swap(uint256[] memory amounts, Route[] memory routes, address _to) internal virtual {
        for (uint256 i; i < routes.length - 1; i++) {
            (address token0,) = sortTokens(routes[i].from, routes[i].to);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = routes[i].from == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < routes.length - 2 ? routes[i + 1].pair : _to;
            IDeltaSwapPair(routes[i].pair).swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        bytes memory path,
        address to,
        uint256 deadline
    ) external virtual /*override*/ ensure(deadline) returns (uint256[] memory amounts) {
        Route[] memory routes;
        (amounts, routes) = getAmountsOut(amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        GammaSwapLibrary.safeTransferFrom(routes[0].from, msg.sender, routes[0].pair, amounts[0]);
        _swap(amounts, routes, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        bytes calldata path,
        address to,
        uint256 deadline
    ) external virtual /*override*/ ensure(deadline) returns (uint256[] memory amounts) {
        Route[] memory routes;
        (amounts, routes) = getAmountsIn(amountOut, path);
        require(amounts[0] <= amountInMax, 'UniversalRouter: EXCESSIVE_INPUT_AMOUNT');
        GammaSwapLibrary.safeTransferFrom(routes[0].from, msg.sender, routes[0].pair, amounts[0]);
        _swap(amounts, routes, to);
    }

    function swapExactETHForTokens(uint256 amountOutMin, bytes calldata path, address to, uint256 deadline)
    external
    virtual
    //override
    payable
    ensure(deadline)
    returns (uint256[] memory amounts)
    {
        Route[] memory routes;
        (amounts, routes) = getAmountsOut(msg.value, path);
        require(routes[0].from == WETH, 'UniversalRouter: INVALID_PATH');
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(routes[0].pair, amounts[0]));
        _swap(amounts, routes, to);
    }
    function swapTokensForExactETH(uint256 amountOut, uint256 amountInMax, bytes calldata path, address to, uint256 deadline)
    external
    virtual
    //override
    ensure(deadline)
    returns (uint256[] memory amounts)
    {
        Route[] memory routes;
        (amounts, routes) = getAmountsIn(amountOut, path);
        require(routes[routes.length - 1].to == WETH, 'UniversalRouter: INVALID_PATH');
        require(amounts[0] <= amountInMax, 'UniversalRouter: EXCESSIVE_INPUT_AMOUNT');
        GammaSwapLibrary.safeTransferFrom(routes[0].from, msg.sender, routes[0].pair, amounts[0]);
        _swap(amounts, routes, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        GammaSwapLibrary.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, bytes calldata path, address to, uint256 deadline)
    external
    virtual
    //override
    ensure(deadline)
    returns (uint256[] memory amounts)
    {
        Route[] memory routes;
        (amounts, routes) = getAmountsOut(amountIn, path);
        require(routes[routes.length - 1].to == WETH, 'UniversalRouter: INVALID_PATH');
        require(amounts[amounts.length - 1] >= amountOutMin, 'UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        GammaSwapLibrary.safeTransferFrom(routes[0].from, msg.sender, routes[0].pair, amounts[0]);
        _swap(amounts, routes, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        GammaSwapLibrary.safeTransferETH(to, amounts[amounts.length - 1]);
    }
    function swapETHForExactTokens(uint256 amountOut, bytes calldata path, address to, uint256 deadline)
    external
    virtual
    //override
    payable
    ensure(deadline)
    returns (uint256[] memory amounts)
    {
        Route[] memory routes;
        (amounts, routes) = getAmountsIn(amountOut, path);
        require(routes[0].from == WETH, 'UniversalRouter: INVALID_PATH');
        require(amounts[0] <= msg.value, 'UniversalRouter: EXCESSIVE_INPUT_AMOUNT');
        IWETH(WETH).deposit{value: amounts[0]}();
        assert(IWETH(WETH).transfer(routes[0].pair, amounts[0]));
        _swap(amounts, routes, to);
        if (msg.value > amounts[0]) GammaSwapLibrary.safeTransferETH(msg.sender, msg.value - amounts[0]);// refund dust eth, if any
    }/**/

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(Route[] memory routes, address _to) internal virtual {
        for (uint256 i; i < routes.length - 1; i++) {
            (address input, address output) = (routes[i].from, routes[i].to);
            (address token0,) = sortTokens(input, output);
            IDeltaSwapPair pair = IDeltaSwapPair(routes[i].pair);
            uint256 amountInput;
            uint256 amountOutput;
            { // scope to avoid stack too deep errors
                (uint256 reserveIn, uint256 reserveOut,) = getReserves(factory, routes[i].from, routes[i].to, routes[i].protocolId);
                amountInput = IERC20(input).balanceOf(address(routes[i].pair)) - reserveIn;
                if(routes[i].protocolId == 3) {
                    routes[i].fee = uint24(calcPairTradingFee(amountInput, reserveIn, reserveOut, routes[i].pair));
                }
                amountOutput = getAmountOut(amountInput, reserveIn, reserveOut, routes[i].fee);
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            address to = i < routes.length - 2 ? routes[i + 1].pair : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        bytes calldata path,
        address to,
        uint256 deadline
    ) external virtual /*override*/ ensure(deadline) {
        Route[] memory routes;
        (,routes) = getAmountsOut(amountIn, path);
        GammaSwapLibrary.safeTransferFrom(routes[0].from, msg.sender, routes[0].pair, amountIn);
        uint256 balanceBefore = IERC20(routes[routes.length - 1].to).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(routes, to);
        require(
            IERC20(routes[path.length - 1].to).balanceOf(to) - balanceBefore >= amountOutMin,
            'UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        bytes calldata path,
        address to,
        uint256 deadline
    )
    external
    virtual
    //override
    payable
    ensure(deadline)
    {
        uint256 amountIn = msg.value;
        IWETH(WETH).deposit{value: amountIn}();

        Route[] memory routes;
        (,routes) = getAmountsOut(amountIn, path);
        require(routes[0].from == WETH, 'UniversalRouter: INVALID_PATH');

        assert(IWETH(WETH).transfer(routes[0].pair, amountIn));
        uint256 balanceBefore = IERC20(routes[routes.length - 1].to).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(routes, to);
        require(
            IERC20(routes[routes.length - 1].to).balanceOf(to) - balanceBefore >= amountOutMin,
            'UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        bytes calldata path,
        address to,
        uint256 deadline
    )
    external
    virtual
    //override
    ensure(deadline)
    {
        Route[] memory routes;
        (,routes) = getAmountsOut(amountIn, path);

        require(routes[routes.length - 1].to == WETH, 'UniversalRouter: INVALID_PATH');
        GammaSwapLibrary.safeTransferFrom(routes[0].from, msg.sender, routes[0].pair, amountIn);
        _swapSupportingFeeOnTransferTokens(routes, address(this));

        uint256 amountOut = IERC20(WETH).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWETH(WETH).withdraw(amountOut);
        GammaSwapLibrary.safeTransferETH(to, amountOut);
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