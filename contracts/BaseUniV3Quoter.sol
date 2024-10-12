// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import '@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/libraries/SafeCast.sol';
import './libraries/CallbackValidation.sol';
import './libraries/PoolTicksCounter.sol';
import './libraries/TickMath.sol';
import './BaseRouter.sol';

abstract contract BaseUniV3Quoter is BaseRouter {

    using Path2 for bytes;
    using PoolTicksCounter for IUniswapV3Pool;
    using SafeCast for uint256;

    /// @dev Transient storage variable used to check a safety condition in exact output swaps.
    uint256 private amountOutCached;

    function quoteExactInputSingle2(uint256 amount, address pool, bool zeroForOne, bytes memory data, bool isReverse)
    public returns (uint256 amountOut, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate)
    {
        if (isReverse) amountOutCached = amount;

        uint256 gasBefore = gasleft();
        try
            IUniswapV3Pool(pool).swap(
                address(this), // address(0) might cause issues with some tokens
                zeroForOne,
                isReverse ? -amount.toInt256() : amount.toInt256(),
                (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
                data
            )
        {} catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            if (isReverse) delete amountOutCached; // clear cache
            return handleRevert(reason, IUniswapV3Pool(pool), gasEstimate);
        }
    }

    /// @dev Parses a revert reason that should contain the numeric quote
    function parseRevertReason(bytes memory reason) private pure returns (uint256 amount, uint160 sqrtPriceX96After, int24 tickAfter) {
        if (reason.length != 96) {
            if (reason.length < 68) revert('Unexpected error');
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (uint256, uint160, int24));
    }

    function handleRevert(bytes memory reason, IUniswapV3Pool pool, uint256 gasEstimate) private view returns (
        uint256 amount, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256) {
        int24 tickBefore;
        int24 tickAfter;
        (, tickBefore, , , , , ) = pool.slot0();
        (amount, sqrtPriceX96After, tickAfter) = parseRevertReason(reason);

        initializedTicksCrossed = pool.countInitializedTicksCrossed(tickBefore, tickAfter);

        return (amount, sqrtPriceX96After, initializedTicksCrossed, gasEstimate);
    }

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory _data
    ) external override {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        (address tokenIn, address tokenOut, uint16 protocolId, uint24 fee) = data.path.decodeFirstPool();
        CallbackValidation.verifyCallback(getFactory(protocolId), tokenIn, tokenOut, fee);

        (bool isExactInput, uint256 amountToPay, uint256 amountReceived) =
        amount0Delta > 0
        ? (tokenIn < tokenOut, uint256(amount0Delta), uint256(-amount1Delta))
        : (tokenOut < tokenIn, uint256(amount1Delta), uint256(-amount0Delta));

        (uint160 sqrtPriceX96After, int24 tickAfter, , , , , ) = IUniswapV3Pool(getPair(tokenIn, tokenOut, protocolId, fee)).slot0();
        if (isExactInput) {
            assembly {
                let ptr := mload(0x40)
                mstore(ptr, amountReceived)
                mstore(add(ptr, 0x20), sqrtPriceX96After)
                mstore(add(ptr, 0x40), tickAfter)
                revert(ptr, 96)
            }
        } else {
            // if the cache has been populated, ensure that the full output amount has been received
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
