// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IUniversalRouter {

    event ProtocolRegistered(uint16 indexed protocolId, address protocol);

    struct Route {
        address pair;
        address from;
        address to;
        uint16 protocolId;
        uint24 fee;
        address dest;
        address hop;
    }

    function protocols(uint16 protocolId) external view returns(address);

    function addProtocol(uint16 protocolId, address protocol) external;

    function swapExactETHForTokens(uint256 amountOutMin, bytes calldata path, address to, uint256 deadline) external payable;

    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, bytes calldata path, address to, uint256 deadline) external;

    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, bytes calldata path, address to, uint256 deadline) external;

    function calcRoutes(uint256 amountIn, bytes memory path, address _to) external view returns (Route[] memory routes);

    function getAmountsOut(uint256 amountIn, bytes memory path) external returns (uint256[] memory amounts, Route[] memory routes);

    function getAmountsIn(uint256 amountOut, bytes memory path) external returns (uint256[] memory amounts, Route[] memory routes);
}
