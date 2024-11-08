// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '@gammaswap/v1-core/contracts/libraries/GSMath.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import '@uniswap/v3-core/contracts/libraries/SafeCast.sol';
import '../interfaces/external/IAeroCLPool.sol';
import '../libraries/AeroCallbackValidation.sol';
import '../libraries/AeroPoolAddress.sol';
import '../libraries/AeroPoolTicksCounter.sol';
import '../libraries/BytesLib2.sol';
import '../libraries/Path2.sol';
import '../libraries/PoolTicksCounter.sol';
import '../libraries/TickMath.sol';
import './CPMMRoute.sol';

/// @title Aerodrome Concentrated Liquidity Protocol Route contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Route contract to implement swaps in Aerodrome Concentrated Liquidity AMMs
/// @dev Implements IProtocolRoute functions to quote and handle one AMM swap at a time
contract AerodromeCL is CPMMRoute, IUniswapV3SwapCallback {

    using BytesLib2 for bytes;
    using Path2 for bytes;
    using AeroPoolTicksCounter for IAeroCLPool;
    using SafeCast for uint256;

    /// @dev Instructions to determine token transfers from swap
    struct SwapCallbackData {
        /// @dev swap path of Aerodrome pools
        bytes path;
        /// @dev address funding swap
        address payer;
    }

    /// @dev Parameters with swap instructions
    struct SwapParams {
        /// @dev address of token swapped in
        address tokenIn;
        /// @dev address of token swapped out
        address tokenOut;
        /// @dev tick spacing of AMM (used to identify AMM)
        uint24 tickSpacing;
        /// @dev amount of tokenIn swapped in
        uint256 amount;
        /// @dev address receiving output of swap in tokenOut
        address recipient;
    }

    /// @dev address of Aerodrome Concentrated Liquidity factory contract
    address public immutable factory;

    /// @dev Transient storage variable used to check a safety condition in exact output swaps.
    uint256 private amountOutCached;

    /// @dev Initialize `_protocolId`, `_factory`, and `WETH` address
    constructor(uint16 _protocolId, address _factory, address _WETH) Transfers(_WETH) {
        protocolId = _protocolId;
        factory = _factory;
    }

    /// @inheritdoc IProtocolRoute
    function quote(uint256 amountIn, address tokenIn, address tokenOut, uint24 fee) public override virtual view returns (uint256 amountOut) {
        (uint256 sqrtPriceX96,,,,,) = IAeroCLPool(_pairFor(tokenIn, tokenOut, fee)).slot0();
        if(tokenIn < tokenOut) {
            uint256 decimals = 10**GammaSwapLibrary.decimals(tokenIn);
            uint256 price = decodePrice(sqrtPriceX96, decimals);
            amountOut = amountIn * price / decimals;
        } else {
            uint256 decimals = 10**GammaSwapLibrary.decimals(tokenOut);
            uint256 price = decodePrice(sqrtPriceX96, decimals);
            amountOut = amountIn * decimals / price;
        }
    }

    /// @dev Assume sqrtPriceX96 is given as input
    /// @param sqrtPriceX96 - square root of price (in terms of token1) in AMM encoded with 2^96
    /// @param decimals - decimal factor of token0 (e.g. 10^18 if token0 is 18 decimals)
    /// @return price - decoded sqrtPriceX96
    function decodePrice(uint256 sqrtPriceX96, uint256 decimals) internal pure returns (uint256 price) {
        // Step 1: Convert sqrtPriceX96 to price ratio
        uint256 sqrtPrice = sqrtPriceX96 * GSMath.sqrt(decimals) / (2**96);

        // Step 2: Divide by 2^192 (since sqrtPriceX96 was scaled by 2^96, we need to square that scale factor)
        price = sqrtPrice * sqrtPrice;
    }

    /// @inheritdoc IProtocolRoute
    function pairFor(address tokenA, address tokenB, uint24 fee) public override virtual view returns (address pair, address token0, address token1) {
        int24 tickSpacing = int24(fee);
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pair = AeroPoolAddress.computeAddress(factory, AeroPoolAddress.PoolKey({token0: token0, token1: token1, tickSpacing: tickSpacing}));
        require(GammaSwapLibrary.isContract(pair), 'AerodromeCL: AMM_DOES_NOT_EXIST');
    }

    /// @dev return only the pair address when calling pairFor
    function _pairFor(address token0, address token1, uint24 fee) internal virtual view returns(address pair) {
        (pair,,) = pairFor(token0, token1, fee);
    }

    /// @inheritdoc IProtocolRoute
    function getOrigin(address tokenA, address tokenB, uint24 fee) external override virtual view
        returns(address pair, address origin) {
        (pair,,) = pairFor(tokenA, tokenB, fee);
        origin = address(this);
    }

    /// @dev Parses a revert reason that should contain the numeric quote
    /// @param reason - revert reason to parse to obtain revert code/message or swap outputs
    /// @return amount - output amount from swap
    /// @return sqrtPriceX96After - price after swap
    /// @return tickAfter - pool tick after swap
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

    /// @dev handle revert after swap
    /// @param reason - revert reason from quoting swap
    /// @param pair - address of AMM
    /// @return amount - output amount from swap
    /// @return sqrtPriceX96After - price after swap
    /// @return initializedTicksCrossed - ticks crossed
    function handleRevert(bytes memory reason, address pair) private view
        returns (uint256 amount, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed){
        int24 tickBefore;
        int24 tickAfter;
        (, tickBefore, , , ,) = IAeroCLPool(pair).slot0();
        (amount, sqrtPriceX96After, tickAfter) = parseRevertReason(reason);

        initializedTicksCrossed = IAeroCLPool(pair).countInitializedTicksCrossed(tickBefore, tickAfter);

        return (amount, sqrtPriceX96After, initializedTicksCrossed);
    }

    /// @inheritdoc IProtocolRoute
    function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut, uint256 fee) public override
        virtual returns(uint256 amountOut, address pair, uint24 swapFee) {
        swapFee = uint24(fee);
        (amountOut, pair) = _quoteAmountOut(amountIn, tokenIn, tokenOut, swapFee);
    }

    /// @notice Calculate amountOut of tokenOut that will be received from swapping in amountIn in tokenIn
    /// @dev Works by simulating a transaction and causing a revert instead of transfer of token amounts
    /// @dev The reason for the revert contains the amount in tokenOut that will be received in exchange for the amountIn
    /// @param amountIn - amount of tokenIn to swap in
    /// @param tokenIn - token to swap into AMM pool
    /// @param tokenOut - token to swap out of AMM pool
    /// @param fee - fee charged by AMM, used to identify AMM in Aerodrome CL
    /// @return amountOut - amount of tokenOut that will be received from the swap
    /// @return pair - address of AMM contract in Aerodrome CL
    function _quoteAmountOut(uint256 amountIn, address tokenIn, address tokenOut, uint24 fee) internal virtual
        returns(uint256 amountOut, address pair) {

        bool zeroForOne = tokenIn < tokenOut;
        (pair,,) = pairFor(tokenIn, tokenOut, fee);

        try
            IAeroCLPool(pair).swap(
                address(this), // address(0) might cause issues with some tokens
                zeroForOne,
                amountIn.toInt256(),
                zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                abi.encode(SwapCallbackData({
                    path: abi.encodePacked(tokenIn, protocolId, fee, tokenOut),
                    payer: address(0)
                }))
            )
        {} catch (bytes memory reason) {
            (amountOut,,) = handleRevert(reason, pair);
        }
    }

    /// @inheritdoc IProtocolRoute
    function getAmountIn(uint256 amountOut, address tokenIn, address tokenOut, uint256 fee) public
        override virtual returns(uint256 amountIn, address pair, uint24 swapFee) {
        swapFee = uint24(fee);
        (amountIn, pair) = _quoteAmountIn(amountOut, tokenIn, tokenOut, swapFee);
    }

    /// @notice Calculate amountIn of tokenIn to swap for amountOut of tokenOut
    /// @dev Works by simulating a transaction and causing a revert instead of transfer of token amounts
    /// @dev The reason for the revert contains the amount in tokenIn that would need to be swapped in
    /// @param amountOut - amount of tokenOut desired to get
    /// @param tokenIn - token to swap into AMM pool
    /// @param tokenOut - token to swap out of AMM pool
    /// @param fee - fee charged by AMM, used to identify AMM in Aerodrome CL
    /// @return amountIn - amount of tokenIn to swap in to get amountOut in tokenOut
    /// @return pair - address of AMM contract in Aerodrome CL
    function _quoteAmountIn(uint256 amountOut, address tokenIn, address tokenOut, uint24 fee) internal virtual
        returns(uint256 amountIn, address pair) {
        (pair,,) = pairFor(tokenIn, tokenOut, fee);

        // if no price limit has been specified, cache the output amount for comparison in the swap callback
        amountOutCached = amountOut;
        try
            IAeroCLPool(pair).swap(
                address(this), // address(0) might cause issues with some tokens
                tokenIn < tokenOut, // zeroForOne
                -amountOut.toInt256(),
                tokenIn < tokenOut ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
                abi.encode(SwapCallbackData({
                    path: abi.encodePacked(tokenOut, protocolId, fee, tokenIn),
                    payer: address(0)
                }))
            )
        {} catch (bytes memory reason) {
            delete amountOutCached; // clear cache
            (amountIn,,) = handleRevert(reason, pair);
        }
    }

    /// @inheritdoc IProtocolRoute
    function swap(address from, address to, uint24 fee, address dest) external override virtual {
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

    /// @dev Swap exact amount of input token for an amount in output tokens
    /// @param params - swap parameters containing quantity to swap
    /// @return amount being swapped in AMM
    function exactInputSwap(SwapParams memory params) private returns (uint256) {
        require(params.amount < 2**255, 'INVALID_AMOUNT');
        require(params.recipient != address(0), 'INVALID_RECIPIENT');

        bool zeroForOne = params.tokenIn < params.tokenOut;

        (int256 amount0, int256 amount1) =
            IAeroCLPool(_pairFor(params.tokenIn, params.tokenOut, params.tickSpacing)).swap(
                params.recipient,
                zeroForOne,
                int256(params.amount),
                (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
                abi.encode(SwapCallbackData({
                    path: abi.encodePacked(params.tokenIn, protocolId, params.tickSpacing, params.tokenOut),
                    payer: address(this)
                }))
            );

        return uint256(-(zeroForOne ? amount1 : amount0));
    }

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes memory _data) external override {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        (address tokenIn, address tokenOut,,uint24 fee) = data.path.decodeFirstPool();
        AeroCallbackValidation.verifyCallback(factory, tokenIn, tokenOut, int24(fee));

        (bool isExactInput, uint256 amountToPay, uint256 amountReceived) =
        amount0Delta > 0
        ? (tokenIn < tokenOut, uint256(amount0Delta), uint256(-amount1Delta))
        : (tokenOut < tokenIn, uint256(amount1Delta), uint256(-amount0Delta));

        (uint160 sqrtPriceX96After, int24 tickAfter,,,,) = IAeroCLPool(_pairFor(tokenIn, tokenOut, fee)).slot0();

        if (isExactInput) {
            if(data.payer != address(0)) {
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
