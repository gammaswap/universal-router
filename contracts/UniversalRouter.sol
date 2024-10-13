// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol";
import "@gammaswap/v1-periphery/contracts/interfaces/external/IWETH.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import "@uniswap/v3-core/contracts/libraries/SafeCast.sol";

import './interfaces/IAeroPool.sol';
import './libraries/CallbackValidation.sol';
import './libraries/PoolAddress.sol';
import './libraries/PoolTicksCounter.sol';
import './libraries/RouterLibrary.sol';
import './libraries/TickMath.sol';
import './BaseRouter.sol';

contract UniversalRouter is BaseRouter, IUniswapV3SwapCallback {

    using Path2 for bytes;
    using BytesLib2 for bytes;
    using SafeCast for uint256;
    using PoolTicksCounter for IUniswapV3Pool;

    /// @dev Transient storage variable used to check a safety condition in exact output swaps.
    uint256 private amountOutCached;

    constructor(address _uniFactory, address _sushiFactory, address _dsFactory, address _aeroFactory, address _uniV3Factory, address _WETH)
        BaseRouter(_uniFactory, _sushiFactory, _dsFactory, _aeroFactory, _uniV3Factory, _WETH) {
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'DeltaSwapRouter: EXPIRED');
        _;
    }

    /// @dev this supports transfer fees tokens too
    function calcRoutes(uint256 amountIn, bytes memory path, address _to) public virtual view returns (Route[] memory routes) {
        require(path.length >= 45 && (path.length - 20) % 25 == 0, "INVALID_PATH");
        routes = new Route[](path.numPools() + 1);
        // transferFrom here first
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
                routes[i].to, routes[i].protocolId, routes[i].fee);

            if(i > 0) {
                routes[i - 1].dest = dest;
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

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens2(Route[] memory routes) internal virtual {
        for (uint256 i; i < routes.length - 1; i++) {
            if(routes[i].protocolId == 6) {
                uint256 inputAmount = IERC20(routes[i].from).balanceOf(address(this));
                bool zeroForOne = routes[i].from < routes[i].to;
                IUniswapV3Pool(routes[i].pair).swap(
                    routes[i].dest,
                    zeroForOne,
                    int256(inputAmount),
                    (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
                    abi.encode(SwapCallbackData({
                        path: abi.encodePacked(routes[i].from, routes[i].protocolId, routes[i].fee, routes[i].to),
                        payer: address(this)
                    }))
                );
            } else {
                (address input, address output) = (routes[i].from, routes[i].to);
                (address token0,) = sortTokens(input, output);
                IDeltaSwapPair pair = IDeltaSwapPair(routes[i].pair);
                uint256 amountInput;
                uint256 amountOutput;
                { // scope to avoid stack too deep errors
                    (uint256 reserveIn, uint256 reserveOut,) = getReserves(routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee);
                    amountInput = IERC20(input).balanceOf(address(routes[i].pair)) - reserveIn;
                    if(routes[i].protocolId >=1 && routes[i].protocolId <= 3) {
                        if(routes[i].protocolId == 3) {
                            routes[i].fee = uint24(DSLib.calcPairTradingFee(amountInput, reserveIn, reserveOut, routes[i].pair));
                        }
                        amountOutput = DSLib.getAmountOut(amountInput, reserveIn, reserveOut, routes[i].fee);
                    } else if(routes[i].protocolId == 5 || routes[i].protocolId == 6) {
                        amountOutput = IAeroPool(routes[i].pair).getAmountOut(amountInput, routes[i].from);
                    }
                }
                (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
                pair.swap(amount0Out, amount1Out, routes[i].dest, new bytes(0));
            }
        }
    }
    /// @dev this is the main function we'll use to swap
    function swapExactTokensForTokensSupportingFeeOnTransferTokens2(
        uint256 amountIn,
        uint256 amountOutMin,
        bytes calldata path,
        address to,
        uint256 deadline
    ) external virtual /*override*/ ensure(deadline) {
        Route[] memory routes = calcRoutes(amountIn, path, to);
        GammaSwapLibrary.safeTransferFrom(routes[0].from, msg.sender, routes[0].dest, amountIn);
        uint256 balanceBefore = IERC20(routes[routes.length - 1].to).balanceOf(to);
        _swapSupportingFeeOnTransferTokens2(routes);
        require(
            IERC20(routes[path.length - 1].to).balanceOf(to) - balanceBefore >= amountOutMin,
            'UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes calldata _data
    ) external override {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        (address tokenIn, address tokenOut,, uint24 fee) = data.path.decodeFirstPool();
        CallbackValidation.verifyCallback(uniFactory, tokenIn, tokenOut, fee);

        (bool isExactInput, uint256 amountToPay) =
            amount0Delta > 0
                ? (tokenIn < tokenOut, uint256(amount0Delta))
                : (tokenOut < tokenIn, uint256(amount1Delta));

        pay(tokenIn, data.payer, msg.sender, amountToPay);
    }

    /// @dev Performs a single exact input swap
    function exactInputInternal(
        uint256 amountIn,
        address recipient,
        uint160 sqrtPriceLimitX96,
        SwapCallbackData memory data
    ) private returns (uint256 amountOut) {
        /*require(amountIn < 2**255, "Invalid amount");
        // allow swapping to the router address with address 0
        if (recipient == address(0)) recipient = address(this);

        (address tokenIn, address tokenOut,,uint24 fee) = data.path.decodeFirstPool();

        bool zeroForOne = tokenIn < tokenOut;

        (int256 amount0, int256 amount1) =
        getPool(tokenIn, tokenOut, fee).swap(
            recipient,
            zeroForOne,
            int256(amountIn),
            sqrtPriceLimitX96 == 0
            ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
            : sqrtPriceLimitX96,
            abi.encode(data)
        );

        return uint256(-(zeroForOne ? amount1 : amount0));/**/
    }

    function pay(
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        if (token == WETH && address(this).balance >= value) {
            // pay with WETH
            IWETH(WETH).deposit{value: value}(); // wrap only what is needed to pay
            IWETH(WETH).transfer(recipient, value);
        } else if (payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            GammaSwapLibrary.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            GammaSwapLibrary.safeTransferFrom(token, payer, recipient, value);
        }
    }
}
