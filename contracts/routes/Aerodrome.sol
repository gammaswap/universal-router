pragma solidity ^0.8.0;

import '@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol';
import "@openzeppelin/contracts/proxy/Clones.sol";
import "../interfaces/IAeroPool.sol";
import "../interfaces/IAeroPoolFactory.sol";
import "../interfaces/IProtocolRoute.sol";
import "../libraries/AeroLib.sol";
import "./CPMMRoute.sol";

contract Aerodrome is CPMMRoute, IProtocolRoute {

    uint16 public immutable protocolId;
    address public immutable factory;
    address public immutable implementation;
    bool public immutable isStable;

    constructor(uint16 _protocolId, address _factory, address _implementation, bool _isStable) {
        protocolId = _protocolId;
        factory = _factory;
        implementation = _implementation;
        isStable = _isStable;
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(address tokenA, address tokenB) internal view returns (address pair, address token0, address token1) {
        (token0, token1) = sortTokens(tokenA, tokenB);
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, isStable));
        pair = Clones.predictDeterministicAddress(implementation, salt, factory);
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address tokenA, address tokenB) internal view returns (uint256 reserve0, uint256 reserve1, address pair) {
        (pair,,) = pairFor(tokenA, tokenB);
        (reserve0, reserve1,) = IAeroPool(pair).getReserves();
    }

    function getAmountOut(uint256 amountIn, address tokenA, address tokenB, uint16 protocolId, uint256 fee) public override virtual
        returns(uint256 amountOut, address pair, uint24 swapFee) {
        (,,pair) = pairFor(tokenA, tokenB);
        swapFee = 3000; // for information purposes only, matches UniV3 format
        amountOut = IAeroPool(pair).getAmountOut(amountIn, tokenA);
    }

    function getAmountIn(uint256 amountOut, address tokenA, address tokenB, uint16 protocolId, uint256 fee) public override virtual
        returns(uint256 amountIn, address pair, uint24 swapFee) {
        uint256 reserveIn;
        uint256 reserveOut;
        (reserveIn, reserveOut, pair) = getReserves(tokenA, tokenB);
        fee = IAeroPoolFactory(factory).getFee(pair, isStable);
        amountIn = AeroLib.getAmountIn(amountOut, reserveIn, reserveOut, 10**GammaSwapLibrary.decimals(tokenA),
            10**GammaSwapLibrary.decimals(tokenB), isStable, fee);
        swapFee = uint24(fee);
    }

    function getDestination(address tokenA, address tokenB, uint16 protocolId, uint24 fee) external override virtual view
        returns(address pair, address dest) {
        (pair,,) = pairFor(tokenA, tokenB);
        dest = pair;
    }

    function swap(address from, address to, uint24 fee, address dest) external override virtual {
        (address pair, address token0,) = pairFor(from, to);
        uint256 amountInput;
        uint256 amountOutput;
        { // scope to avoid stack too deep errors
            (uint256 reserveIn, uint256 reserveOut,) = getReserves(from, to);
            amountInput = GammaSwapLibrary.balanceOf(from, pair) - reserveIn;
            amountOutput = IAeroPool(pair).getAmountOut(amountInput, from);
        }
        (uint256 amount0Out, uint256 amount1Out) = from == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
        IAeroPool(pair).swap(amount0Out, amount1Out, dest, new bytes(0));
    }
}
