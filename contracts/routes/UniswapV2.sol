// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '@gammaswap/v1-implementations/contracts/interfaces/external/cpmm/ICPMM.sol';
import './CPMMRoute.sol';

/// @title UniswapV2 Protocol Route contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Route contract to implement swaps in UniswapV2 AMMs
/// @dev Implements IProtocolRoute functions to quote and handle one AMM swap at a time
contract UniswapV2 is CPMMRoute {

    /// @dev address of UniswapV2 factory contract
    address public immutable factory;

    /// @dev Initialize `_protocolId`, `_factory`, and `WETH` address
    constructor(uint16 _protocolId, address _factory, address _WETH) Transfers(_WETH) {
        protocolId = _protocolId;
        factory = _factory;
    }

    /// @dev init code hash of UniswapV2 pools. Used to calculate pool address without external calls
    function initCodeHash() internal virtual pure returns(bytes32) {
        return 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
    }

    /// @inheritdoc IProtocolRoute
    function quote(uint256 amountIn, address tokenIn, address tokenOut, uint24 fee) public override virtual view returns (uint256 amountOut) {
        (uint256 reserveIn, uint256 reserveOut,) = getReserves(tokenIn, tokenOut);
        amountOut = _quote(amountIn, reserveIn, reserveOut);
    }

    /// @dev Get AMM for tokenA and tokenB pair. Calculated using CREATE2 address for the pair without making any external calls
    /// @dev Also return sorted token pair
    /// @param tokenA - address of a token of the AMM pool
    /// @param tokenB - address of other token of the AMM pool
    /// @return pair - address of AMM for token pair
    /// @return token0 - address of token in the AMM of lower value
    /// @return token1 - address of token in the AMM of higher value
    function pairFor(address tokenA, address tokenB) internal view returns (address pair, address token0, address token1) {
        (token0, token1) = _sortTokens(tokenA, tokenB);
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            factory,
            keccak256(abi.encodePacked(token0, token1)),
            initCodeHash() // init code hash for V2 type protocols
        )))));
        require(GammaSwapLibrary.isContract(pair), 'UniswapV2: AMM_DOES_NOT_EXIST');
    }

    /// @dev Fetches and sorts the reserves for a pair
    /// @param tokenA - address of first token in the AMM
    /// @param tokenB - address of other token in the AMM
    /// @return reserveA - reserve of tokenA in AMM
    /// @return reserveB - reserve of tokenB in AMM
    /// @return pair - address of AMM of tokenA and tokenB pair
    function getReserves(address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB, address pair) {
        address token0;
        (pair, token0,) = pairFor(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = ICPMM(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /// @inheritdoc IProtocolRoute
    function getAmountOut(uint256 amountIn, address tokenA, address tokenB, uint256 fee) public override virtual
        returns(uint256 amountOut, address pair, uint24 swapFee) {
        uint256 reserveIn;
        uint256 reserveOut;
        (reserveIn, reserveOut, pair) = getReserves(tokenA, tokenB);
        swapFee = 3000; // for information purposes only, matches UniV3 format
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
    }

    /// @inheritdoc IProtocolRoute
    function getAmountIn(uint256 amountOut, address tokenA, address tokenB, uint256 fee) public override virtual
        returns(uint256 amountIn, address pair, uint24 swapFee) {
        uint256 reserveIn;
        uint256 reserveOut;
        (reserveIn, reserveOut, pair) = getReserves(tokenA, tokenB);
        swapFee = 3000; // for information purposes only, matches UniV3 format
        amountIn = _getAmountIn(amountOut, reserveIn, reserveOut);
    }

    /// @inheritdoc IProtocolRoute
    function getOrigin(address tokenA, address tokenB, uint24 fee) external override virtual view
        returns(address pair, address origin) {
        (pair,,) = pairFor(tokenA, tokenB);
        origin = pair;
    }

    /// @dev Given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    /// @param amountIn - amount of token being swapped in
    /// @param reserveIn - reserve amount of token swapped in
    /// @param reserveOut - reserve amount of token swapped out
    /// @return amountOut - amount of token being swapped out
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY');
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    /// @dev Given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    /// @param amountOut - amount desired to swap out
    /// @param reserveIn - reserve amount of token swapped in
    /// @param reserveOut - reserve amount of token swapped out
    /// @return amountIn - amount of token to swap in to get amountOut
    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY');
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    /// @inheritdoc IProtocolRoute
    function swap(address from, address to, uint24 fee, address dest) external override virtual {
        (address pair, address token0,) = pairFor(from, to);
        uint256 amountInput;
        uint256 amountOutput;
        { // scope to avoid stack too deep errors
            (uint256 reserveIn, uint256 reserveOut,) = getReserves(from, to);
            amountInput = GammaSwapLibrary.balanceOf(from, pair) - reserveIn;
            amountOutput = _getAmountOut(amountInput, reserveIn, reserveOut);
        }
        (uint256 amount0Out, uint256 amount1Out) = from == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
        ICPMM(pair).swap(amount0Out, amount1Out, dest, new bytes(0));
    }
}
