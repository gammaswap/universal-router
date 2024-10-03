// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "./UniswapSetup.sol";

contract TestBed is UniswapSetup {
    event ExternalRebalanceSingleSwap(
        address indexed sender,
        address indexed caller,
        uint256 indexed tokenId,
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountIn,
        uint256 amountOut,
        bool isBuy
    );
    struct SingleSwapEventParams {
        address sender;
        address caller;
        uint256 tokenId;
        address tokenIn;
        address tokenOut;
        uint24 poolFee;
        uint256 amountIn;
        uint256 amountOut;
        bool isBuy;
    }
    event ExternalRebalanceSwap(
        address indexed sender,
        address indexed caller,
        uint256 indexed tokenId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        bool isBuy
    );
    struct MultihopSwapEventParams {
        address sender;
        address caller;
        uint256 tokenId;
        address tokenIn;
        address tokenOut;
        uint256 amountIn;
        uint256 amountOut;
        bool isBuy;
    }

    function initSetup(address owner) public {
        initTokens();
        initUniswapV3(owner);
        initUniswap(owner);
    }
}