pragma solidity ^0.8.0;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3SwapCallback.sol';
import '@uniswap/v3-core/contracts/libraries/SafeCast.sol';
import '@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol';
import "@gammaswap/v1-periphery/contracts/interfaces/external/IWETH.sol";
import '../libraries/CallbackValidation.sol';
import '../libraries/PoolTicksCounter.sol';
import '../libraries/TickMath.sol';
import './CPMMRoute.sol';
import '../interfaces/IProtocolRoute.sol';
import '../libraries/BytesLib2.sol';
import '../libraries/Path2.sol';

contract UniswapV3 is CPMMRoute, IProtocolRoute, IUniswapV3SwapCallback {

    using BytesLib2 for bytes;
    using Path2 for bytes;
    using PoolTicksCounter for IUniswapV3Pool;
    using SafeCast for uint256;

    struct SwapCallbackData {
        bytes path;
        address payer;
    }

    uint16 public immutable override protocolId;
    address public immutable factory;
    bytes32 internal constant POOL_INIT_CODE_HASH = 0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54;

    address public immutable WETH;

    /// @dev Transient storage variable used to check a safety condition in exact output swaps.
    uint256 private amountOutCached;

    constructor(uint16 _protocolId, address _factory, address _WETH){
        protocolId = _protocolId;
        factory = _factory;
        WETH = _WETH;
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address tokenA, address tokenB, uint24 fee) internal view returns (address pair) {
        (tokenA, tokenB) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            factory,
            keccak256(abi.encodePacked(tokenA, tokenB, fee)),
            POOL_INIT_CODE_HASH // init code hash for V2 type protocols
        )))));
        require(GammaSwapLibrary.isContract(pair), "AMM_DOES_NOT_EXIST");
    }

    /// @inheritdoc IUniswapV3SwapCallback
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes memory _data) external override {
        require(amount0Delta > 0 || amount1Delta > 0); // swaps entirely within 0-liquidity regions are not supported
        SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
        (address tokenIn, address tokenOut,,uint24 fee) = data.path.decodeFirstPool();
        CallbackValidation.verifyCallback(factory, tokenIn, tokenOut, fee);

        (bool isExactInput, uint256 amountToPay, uint256 amountReceived) =
            amount0Delta > 0
                ? (tokenIn < tokenOut, uint256(amount0Delta), uint256(-amount1Delta))
                : (tokenOut < tokenIn, uint256(amount1Delta), uint256(-amount0Delta));

        (uint160 sqrtPriceX96After, int24 tickAfter, , , , , ) = IUniswapV3Pool(pairFor(tokenIn, tokenOut, fee)).slot0();

        if (isExactInput) {
            if(data.payer != address(0)) {
                pay(tokenIn, data.payer, msg.sender, amountToPay);
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

    function handleRevert(bytes memory reason, address pair) private view
        returns (uint256 amount, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed){
        int24 tickBefore;
        int24 tickAfter;
        (, tickBefore, , , , , ) = IUniswapV3Pool(pair).slot0();
        (amount, sqrtPriceX96After, tickAfter) = parseRevertReason(reason);

        initializedTicksCrossed = IUniswapV3Pool(pair).countInitializedTicksCrossed(tickBefore, tickAfter);

        return (amount, sqrtPriceX96After, initializedTicksCrossed);
    }

    function getAmountOut(uint256 amountIn, address tokenIn, address tokenOut, uint256 fee) public override
        virtual returns(uint256 amountOut, address pair, uint24 swapFee) {
        swapFee = uint24(fee);
        (amountOut, pair) = _quoteAmountOut(amountIn, tokenIn, tokenOut, swapFee);
    }

    function _quoteAmountOut(uint256 amountIn, address tokenIn, address tokenOut, uint24 fee) internal virtual
        returns(uint256 amountOut, address pair) {

        bool zeroForOne = tokenIn < tokenOut;
        pair = pairFor(tokenIn, tokenOut, fee);

        try
            IUniswapV3Pool(pair).swap(
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

    function getAmountIn(uint256 amountOut, address tokenIn, address tokenOut, uint256 fee) public
        override virtual returns(uint256 amountIn, address pair, uint24 swapFee) {
        swapFee = uint24(fee);
        (amountIn, pair) = _quoteAmountIn(amountOut, tokenIn, tokenOut, swapFee);
    }

    function _quoteAmountIn(uint256 amountOut, address tokenIn, address tokenOut, uint24 fee) internal virtual
        returns(uint256 amountIn, address pair) {
        pair = pairFor(tokenIn, tokenOut, fee);

        // if no price limit has been specified, cache the output amount for comparison in the swap callback
        amountOutCached = amountOut;
        try
            IUniswapV3Pool(pair).swap(
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

    function getDestination(address tokenA, address tokenB, uint24 fee) external override virtual view
        returns(address pair, address dest) {
        pair = pairFor(tokenA, tokenB, fee);
        dest = address(this);
    }

    function swap(address from, address to, uint24 fee, address dest) external override virtual {
        uint256 inputAmount = GammaSwapLibrary.balanceOf(from, address(this));
        exactInputSwap(inputAmount, from, to, fee, dest);
    }

    function exactInputSwap(uint256 amountIn, address tokenIn, address tokenOut, uint24 fee, address recipient)
        private returns (uint256 amountOut) {
        require(amountIn < 2**255, "Invalid amount");
        // allow swapping to the router address with address 0
        if (recipient == address(0)) recipient = address(this);

        IUniswapV3Pool(pairFor(tokenIn, tokenOut, fee)).swap(
            recipient,
            tokenIn < tokenOut,
            int256(amountIn),
            (tokenIn < tokenOut ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1),
            abi.encode(SwapCallbackData({
                path: abi.encodePacked(tokenIn, protocolId, fee, tokenOut),
                payer: address(this)
            }))
        );
    }

    function pay(address token, address payer, address recipient, uint256 value) internal {
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
