// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IProtocolRoute {
    function protocolId() external view returns(uint16);

    function getAmountOut(uint256 amountIn, address tokenA, address tokenB, uint16 protocolId, uint256 fee) external
        returns(uint256 amountOut, address pair, uint24 swapFee);

    function getAmountIn(uint256 amountOut, address tokenA, address tokenB, uint16 protocolId, uint256 fee) external
        returns(uint256 amountIn, address pair, uint24 swapFee);

    function getDestination(address tokenA, address tokenB, uint16 protocolId, uint24 fee) external view returns(address, address);
}
