// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import '../../../contracts/test/TestUniversalRouter.sol';
import './UniswapSetup.sol';

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

    TestUniversalRouter router;

    function initSetup(address owner) public {
        initTokens();
        initUniswapV3(owner);
        initUniswap(owner);
        initSushiswap(owner);
        initDeltaSwap(owner);
        initAerodrome(owner);
        initAerodromeCL(owner,aeroVoter);
        initShadowCL(owner);
        router = new TestUniversalRouter(address(weth));
    }

    function boundVar(uint256 x, uint256 min, uint256 max) internal pure virtual returns (uint256) {
        require(min <= max, "min > max");
        // If x is between min and max, return x directly. This is to ensure that dictionary values
        // do not get shifted if the min is nonzero. More info: https://github.com/foundry-rs/forge-std/issues/188
        if (x < min) return min;
        if (x > max) return max;
        return x;
    }
}