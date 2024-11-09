// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '@openzeppelin/contracts/proxy/Clones.sol';
import '../interfaces/external/IAeroPool.sol';
import '../interfaces/external/IAeroPoolFactory.sol';
import '../libraries/AeroLib.sol';
import './CPMMRoute.sol';

/// @title Aerodrome Protocol Route contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Route contract to implement swaps in Aerodrome AMMs
/// @dev Implements IProtocolRoute functions to quote and handle one AMM swap at a time
contract Aerodrome is CPMMRoute {

    /// @dev address of Aerodrome pool used as implementation address by factory contract
    address public immutable implementation;
    /// @dev if set to true, it's for stable token pairs in Aerodrome
    bool public immutable isStable;

    /// @dev Initialize `_protocolId`, `_factory`, `_isStable`, and `WETH` address
    constructor(uint16 _protocolId, address _factory, bool _isStable, address _WETH) Transfers(_WETH) {
        protocolId = _protocolId;
        factory = _factory;
        implementation = IAeroPoolFactory(_factory).implementation();
        isStable = _isStable;
    }

    /// @inheritdoc IProtocolRoute
    function quote(uint256 amountIn, address tokenIn, address tokenOut, uint24 fee) public override virtual view returns (uint256 amountOut) {
        (uint256 reserveIn, uint256 reserveOut,) = getReserves(tokenIn, tokenOut);
        amountOut = _quote(amountIn, reserveIn, reserveOut);
    }

    /// @inheritdoc IProtocolRoute
    function pairFor(address tokenA, address tokenB, uint24 fee) public override virtual view returns (address pair, address token0, address token1) {
        (token0, token1) = _sortTokens(tokenA, tokenB);
        bytes32 salt = keccak256(abi.encodePacked(token0, token1, isStable));
        pair = Clones.predictDeterministicAddress(implementation, salt, factory);
        require(GammaSwapLibrary.isContract(pair), 'Aerodrome: AMM_DOES_NOT_EXIST');
    }

    /// @dev Fetches and sorts the reserves for a pair
    /// @param tokenA - address of first token in the AMM
    /// @param tokenB - address of other token in the AMM
    /// @return reserveA - reserve of tokenA in AMM
    /// @return reserveB - reserve of tokenB in AMM
    /// @return pair - address of AMM of tokenA and tokenB pair
    function getReserves(address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB, address pair) {
        address token0;
        (pair, token0,) = pairFor(tokenA, tokenB, 0);
        (uint256 reserve0, uint256 reserve1,) = IAeroPool(pair).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    /// @inheritdoc IProtocolRoute
    function getAmountOut(uint256 amountIn, address tokenA, address tokenB, uint256 fee) public override virtual
        returns(uint256 amountOut, address pair, uint24 swapFee) {
        (pair,,) = pairFor(tokenA, tokenB, 0);
        swapFee = uint24(IAeroPoolFactory(factory).getFee(pair, isStable));
        amountOut = IAeroPool(pair).getAmountOut(amountIn, tokenA);
    }

    /// @inheritdoc IProtocolRoute
    function getAmountIn(uint256 amountOut, address tokenA, address tokenB, uint256 fee) public override virtual
        returns(uint256 amountIn, address pair, uint24 swapFee) {
        uint256 reserveIn;
        uint256 reserveOut;
        (reserveIn, reserveOut, pair) = getReserves(tokenA, tokenB);
        fee = IAeroPoolFactory(factory).getFee(pair, isStable);
        amountIn = AeroLib.getAmountIn(amountOut, reserveIn, reserveOut, 10**GammaSwapLibrary.decimals(tokenA),
            10**GammaSwapLibrary.decimals(tokenB), isStable, fee);
        swapFee = uint24(fee);
    }

    /// @inheritdoc IProtocolRoute
    function getOrigin(address tokenA, address tokenB, uint24 fee) external override virtual view
        returns(address pair, address origin) {
        (pair,,) = pairFor(tokenA, tokenB, fee);
        origin = pair;
    }

    /// @inheritdoc IProtocolRoute
    function swap(address from, address to, uint24 fee, address dest) external override virtual {
        (address pair, address token0,) = pairFor(from, to, fee);
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
