// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol";
import "@gammaswap/v1-implementations/contracts/interfaces/external/cpmm/ICPMM.sol";

import '../interfaces/IProtocolRoute.sol';
import './CPMMRoute.sol';

contract UniswapV2 is CPMMRoute, IProtocolRoute {

    uint16 public immutable override protocolId;
    address public immutable factory;

    constructor(uint16 _protocolId, address _factory){
        protocolId = _protocolId;
        factory = _factory;
    }

    function initCodeHash() internal virtual pure returns(bytes32) {
        return 0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address tokenA, address tokenB) internal view returns (address pair, address token0, address token1) {
        (token0, token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
            hex'ff',
            factory,
            keccak256(abi.encodePacked(token0, token1)),
            initCodeHash() // init code hash for V2 type protocols
        )))));
        require(GammaSwapLibrary.isContract(pair), "AMM_DOES_NOT_EXIST");
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB, address pair) {
        address token0;
        (pair, token0,) = pairFor(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = ICPMM(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function getAmountOut(uint256 amountIn, address tokenA, address tokenB, uint256 fee) public override virtual
        returns(uint256 amountOut, address pair, uint24 swapFee) {
        uint256 reserveIn;
        uint256 reserveOut;
        (reserveIn, reserveOut, pair) = getReserves(tokenA, tokenB);
        swapFee = 3000; // for information purposes only, matches UniV3 format
        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, address tokenA, address tokenB, uint256 fee) public override virtual
        returns(uint256 amountIn, address pair, uint24 swapFee) {
        uint256 reserveIn;
        uint256 reserveOut;
        (reserveIn, reserveOut, pair) = getReserves(tokenA, tokenB);
        swapFee = 3000; // for information purposes only, matches UniV3 format
        amountIn = _getAmountIn(amountOut, reserveIn, reserveOut);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'DeltaSwapLibrary: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'DeltaSwapLibrary: INSUFFICIENT_LIQUIDITY');
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function _getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, 'DeltaSwapLibrary: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'DeltaSwapLibrary: INSUFFICIENT_LIQUIDITY');
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    function getDestination(address tokenA, address tokenB, uint24 fee) external override virtual view
        returns(address pair, address dest) {
        (dest,,) = pairFor(tokenA, tokenB);
        dest = pair;
    }

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