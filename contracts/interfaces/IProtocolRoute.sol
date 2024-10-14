// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IProtocolRoute {
    function protocolId() external view returns(uint16);

    function getAmountOut(uint256 amountIn, address tokenA, address tokenB, uint256 fee) external
        returns(uint256 amountOut, address pair, uint24 swapFee);

    function getAmountIn(uint256 amountOut, address tokenA, address tokenB, uint256 fee) external
        returns(uint256 amountIn, address pair, uint24 swapFee);

    function getOrigin(address tokenA, address tokenB, uint24 fee) external view returns(address, address);

    function swap(address from, address to, uint24 fee, address dest) external;
}
