// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '@gammaswap/v1-core/contracts/libraries/GSMath.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import '@uniswap/v3-core/contracts/libraries/SafeCast.sol';
import '../interfaces/IProtocolRoute.sol';
import '../interfaces/external/IRamsesV3Pool.sol';
import '../interfaces/external/IRamsesV3Factory.sol';
import '../libraries/ShadowCallbackValidation.sol';
import '../libraries/ShadowPoolAddress.sol';
import '../libraries/ShadowPoolTicksCounter.sol';
import '../libraries/BytesLib2.sol';
import '../libraries/Path2.sol';
import '../libraries/TickMath.sol';
import './CPMMRoute.sol';

contract ShadowCL is CPMMRoute, IUniswapV3SwapCallback {
    using BytesLib2 for bytes;
    using Path2 for bytes;
    using ShadowPoolTicksCounter for IRamsesV3Pool;
    using SafeCast for uint256;

    struct SwapCallbackData {
        bytes path;
        address payer;
    }

    struct SwapParams {
        address tokenIn;
        address tokenOut;
        uint24 tickSpacing;
        uint256 amount;
        address recipient;
    }

    uint256 private amountOutCached;

    constructor(uint16 _protocolId, address _factory, address _WETH) Transfers(_WETH) {
        protocolId = _protocolId;
        factory = _factory; // this is the ramsesV3PoolDeployer
    }

    function quote(uint256 amountIn, address tokenIn, address tokenOut, uint24 fee) public override view returns (uint256 amountOut) {
        (uint256 sqrtPriceX96,,,,,,) = IRamsesV3Pool(_pairFor(tokenIn, tokenOut, fee)).slot0();
        if (tokenIn < tokenOut) {
            uint256 decimals = 10**GammaSwapLibrary.decimals(tokenIn);
            uint256 price = decodePrice(sqrtPriceX96, decimals);
            amountOut = amountIn * price / decimals;
        } else {
            uint256 decimals = 10**GammaSwapLibrary.decimals(tokenOut);
            uint256 price = decodePrice(sqrtPriceX96, decimals);
            amountOut = price == 0 ? type(uint128).max : amountIn * decimals / price;
        }
    }

    function getFee(address tokenIn, address tokenOut, uint24 fee) external override view returns (uint256) {
        (address pair,,) = pairFor(tokenIn, tokenOut, fee);
        return IRamsesV3Pool(pair).fee();
    }

    function decodePrice(uint256 sqrtPriceX96, uint256 decimals) internal pure returns (uint256 price) {
        uint256 sqrtPrice = sqrtPriceX96 * GSMath.sqrt(decimals) / (2**96);
        price = sqrtPrice * sqrtPrice;
    }

    function pairFor(address tokenA, address tokenB, uint24 fee) public override view returns (address pair, address token0, address token1) {
        int24 tickSpacing = int24(fee);
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair = ShadowPoolAddress.computeAddress(factory, ShadowPoolAddress.PoolKey({token0: token0, token1: token1, tickSpacing: tickSpacing}));
        require(GammaSwapLibrary.isContract(pair), 'ShadowCL: AMM_DOES_NOT_EXIST');
    }

    function _pairFor(address token0, address token1, uint24 fee) internal view returns (address pair) {
        (pair,,) = pairFor(token0, token1, fee);
    }

    function getOrigin(address tokenA, address tokenB, uint24 fee) external override view returns (address pair, address origin) {
        (pair,,) = pairFor(tokenA, tokenB, fee);
        origin = address(this);
    }

    function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut, uint256 fee) public override returns (uint256 amountOut, address pair, uint24 swapFee) {
        swapFee = uint24(fee);
        (amountOut, pair) = _quoteAmountOut(amountIn, tokenIn, tokenOut, swapFee);
    }

    function _quoteAmountOut(uint256 amountIn, address tokenIn, address tokenOut, uint24 fee) internal returns (uint256 amountOut, address pair) {
        bool zeroForOne = tokenIn < tokenOut;
        (pair,,) = pairFor(tokenIn, tokenOut, fee);
        try IRamsesV3Pool(pair).swap(
            address(this),
            zeroForOne,
            amountIn.toInt256(),
            zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(SwapCallbackData({path: abi.encodePacked(tokenIn, protocolId, fee, tokenOut), payer: address(0)}))
        ) {} catch (bytes memory reason) {
            (amountOut,,) = handleRevert(reason, pair);
        }
    }

    function getAmountIn(uint256 amountOut, address tokenIn, address tokenOut, uint256 fee) public override returns (uint256 amountIn, address pair, uint24 swapFee) {
        swapFee = uint24(fee);
        (amountIn, pair) = _quoteAmountIn(amountOut, tokenIn, tokenOut, swapFee);
    }

    function _quoteAmountIn(uint256 amountOut, address tokenIn, address tokenOut, uint24 fee) internal returns (uint256 amountIn, address pair) {
        (pair,,) = pairFor(tokenIn, tokenOut, fee);
        amountOutCached = amountOut;
        try IRamsesV3Pool(pair).swap(
            address(this),
            tokenIn < tokenOut,
            -amountOut.toInt256(),
            tokenIn < tokenOut ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(SwapCallbackData({path: abi.encodePacked(tokenOut, protocolId, fee, tokenIn), payer: address(0)}))
        ) {} catch (bytes memory reason) {
            delete amountOutCached;
            (amountIn,,) = handleRevert(reason, pair);
        }
    }

    function handleRevert(bytes memory reason, address pair) private view returns (uint256 amount, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed) {
        int24 tickBefore;
        int24 tickAfter;
        (,tickBefore,,,,,) = IRamsesV3Pool(pair).slot0();
        (amount, sqrtPriceX96After, tickAfter) = parseRevertReason(reason);
        initializedTicksCrossed = IRamsesV3Pool(pair).countInitializedTicksCrossed(tickBefore, tickAfter);
    }

    function parseRevertReason(bytes memory reason) private pure returns (uint256 amount, uint160 sqrtPriceX96After, int24 tickAfter) {
        if (reason.length != 96) {
            if (reason.length < 68) revert('Unexpected error');
            assembly { reason := add(reason, 0x04) }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (uint256, uint160, int24));
    }

    function swap(address from, address to, uint24 fee, address dest) external override {
        uint256 inputAmount = GammaSwapLibrary.balanceOf(from, address(this));
        require(inputAmount > 0, 'ZERO_AMOUNT');

        exactInputSwap(SwapParams({
            tokenIn: from,
            tokenOut: to,
            tickSpacing: fee,
            amount: inputAmount,
            recipient: dest
        }));
    }

    function exactInputSwap(SwapParams memory params) private returns (uint256) {
        require(params.amount < 2**255, 'INVALID_AMOUNT');
        require(params.recipient != address(0), 'INVALID_RECIPIENT');

        bool zeroForOne = params.tokenIn < params.tokenOut;
        (int256 amount0, int256 amount1) = IRamsesV3Pool(_pairFor(params.tokenIn, params.tokenOut, params.tickSpacing)).swap(
            params.recipient,
            zeroForOne,
            int256(params.amount),
            (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
            abi.encode(SwapCallbackData({path: abi.encodePacked(params.tokenIn, protocolId, params.tickSpacing, params.tokenOut), payer: address(this)}))
        );

        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes memory _data) external override {
        require(amount0Delta > 0 || amount1Delta > 0);
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        (address tokenIn, address tokenOut,, uint24 fee) = data.path.decodeFirstPool();
        ShadowCallbackValidation.verifyCallback(factory, tokenIn, tokenOut, int24(fee));

        (bool isExactInput, uint256 amountToPay, uint256 amountReceived) = amount0Delta > 0
            ? (tokenIn < tokenOut, uint256(amount0Delta), uint256(-amount1Delta))
            : (tokenOut < tokenIn, uint256(amount1Delta), uint256(-amount0Delta));

        (uint160 sqrtPriceX96After, int24 tickAfter,,,,,) = IRamsesV3Pool(_pairFor(tokenIn, tokenOut, fee)).slot0();

        if (isExactInput) {
            if (data.payer != address(0)) {
                send(tokenIn, data.payer, msg.sender, amountToPay);
            } else {
                assembly {
                    let ptr := mload(0x40)
                    mstore(ptr, amountReceived)
                    mstore(add(ptr, 0x20), sqrtPriceX96After)
                    mstore(add(ptr, 0x40), tickAfter)
                    revert(ptr, 96)
                }
            }
        } else {
            if (amountOutCached != 0) require(amountReceived == amountOutCached);
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, amountToPay)
                mstore(add(ptr, 0x20), sqrtPriceX96After)
                mstore(add(ptr, 0x40), tickAfter)
                revert(ptr, 96)
            }
        }
    }
}
