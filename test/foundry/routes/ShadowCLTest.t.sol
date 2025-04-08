// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import '../fixtures/TestBed.sol';
import '../../../contracts/test/TestUniversalRouter.sol';
import '../../../contracts/test/routes/TestShadowCL.sol';

contract ShadowCLTest is TestBed {
    address owner;
    TestShadowCL route;

    function setUp() public {
        owner = vm.addr(1);
        initSetup(owner);

        route = new TestShadowCL(8, address(shadowCLPoolDeployer), address(weth));
    }

    function testConstants() public {
        assertEq(route.protocolId(), 8);
        assertEq(route.factory(), address(shadowCLFactory));
        assertEq(route.WETH(), address(weth));
    }

    function testPairFor() public {
        address pair = route.getPairFor(address(usdc), address(weth), shadowCLTickSpacing);
        assertEq(pair, address(shadowCLWethUsdcPool));

        pair = route.getPairFor(address(weth), address(usdc), shadowCLTickSpacing);
        assertEq(pair, address(shadowCLWethUsdcPool));
    }

    function testDecodePrice() public {
        (uint256 sqrtPriceX96,,,,,,) = shadowCLWethUsdcPool.slot0();
        uint8 decimals = GammaSwapLibrary.decimals(shadowCLWethUsdcPool.token0());
        uint256 price = route.getDecodedPrice(sqrtPriceX96, 10**decimals);
        assertApproxEqRel(price, 2999999999, 1e14);
    }

    function testQuote() public {
        uint256 amountIn = 1e18;
        uint256 amountOut = route.quote(amountIn, address(weth), address(usdc), uint24(shadowCLTickSpacing));
        assertGt(amountOut, 0);
    }

    function testGetOrigin() public {
        (address pair, address origin) = route.getOrigin(address(weth), address(usdc), uint24(shadowCLTickSpacing));
        assertEq(pair, address(shadowCLWethUsdcPool));
        assertEq(origin, address(route));
    }

    function testGetAmountOut() public {
        uint256 amountIn = 1e18;
        (uint256 amountOut, address pair, uint24 swapFee) = route.getAmountOut(amountIn, address(weth), address(usdc), uint24(shadowCLTickSpacing));
        assertEq(pair, address(shadowCLWethUsdcPool));
        assertEq(swapFee, uint24(shadowCLTickSpacing));
        assertGt(amountOut, 0);
    }

    function testGetAmountIn() public {
        uint256 amountOut = 1e6;
        (uint256 amountIn, address pair, uint24 swapFee) = route.getAmountIn(amountOut, address(usdc), address(weth), uint24(shadowCLTickSpacing));
        assertEq(pair, address(shadowCLWethUsdcPool));
        assertEq(swapFee, uint24(shadowCLTickSpacing));
        assertGt(amountIn, 0);
    }

    function testSwap() public {
        uint256 amountIn = 1e18;
        deal(address(weth), address(route), amountIn);
        uint256 balanceBefore = usdc.balanceOf(owner);

        vm.startPrank(owner);
        route.swap(address(weth), address(usdc), uint24(shadowCLTickSpacing), owner);
        vm.stopPrank();

        uint256 balanceAfter = usdc.balanceOf(owner);
        assertGt(balanceAfter, balanceBefore);
    }
}
