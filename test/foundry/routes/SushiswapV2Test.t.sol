// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "../fixtures/TestBed.sol";
import "../../../contracts/test/TestUniversalRouter.sol";
import "../../../contracts/test/routes/TestSushiswapV2.sol";

contract SushiswapV2Test is TestBed {

    address owner;
    TestSushiswapV2 route;

    function setUp() public {
        owner = vm.addr(1);
        initSetup(owner);

        route = new TestSushiswapV2(2, address(sushiFactory), address(weth));
    }

    function testConstants() public {
        assertEq(route.protocolId(), 2);
        assertEq(route.factory(), address(sushiFactory));
        assertEq(route.WETH(), address(weth));
        assertEq(route.getInitCodeHash(),0xe18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303);
    }

    function testPairFor() public {
        (address pair, address token0, address token1) = route.getPairFor(address(usdc), address(weth));
        assertEq(pair, address(sushiWethUsdcPool));
        if(address(usdc) < address(weth)) {
            assertEq(token0, address(usdc));
            assertEq(token1, address(weth));
        } else {
            assertEq(token1, address(usdc));
            assertEq(token0, address(weth));
        }

        (pair, token0, token1) = route.getPairFor(address(weth), address(usdc));
        assertEq(pair, address(sushiWethUsdcPool));
        if(address(usdc) < address(weth)) {
            assertEq(token0, address(usdc));
            assertEq(token1, address(weth));
        } else {
            assertEq(token1, address(usdc));
            assertEq(token0, address(weth));
        }
    }

    function testPairForErrors() public {
        vm.expectRevert("CPMMRoute: IDENTICAL_ADDRESSES");
        route.getPairFor(address(weth), address(weth));

        vm.expectRevert("UniswapV2: AMM_DOES_NOT_EXIST");
        route.getPairFor(address(weth), address(vm.addr(123456)));
    }

    function testGetReserves() public {
        (uint256 reserveA0, uint256 reserveB0, address pair0) = route.getPairReserves(address(weth), address(usdc));
        assertEq(pair0, address(sushiWethUsdcPool));
        assertGt(reserveA0, 0);
        assertGt(reserveB0, 0);
        assertNotEq(reserveA0, reserveB0);
        (uint256 reserveA1, uint256 reserveB1, address pair1) = route.getPairReserves(address(usdc), address(weth));
        assertEq(pair1, address(sushiWethUsdcPool));
        assertEq(reserveA0, reserveB1);
        assertEq(reserveB0, reserveA1);
    }

    function testQuote() public {
        uint256 amountIn = 1e18;
        uint256 amountOut = route.quote(amountIn, address(weth), address(usdc), 0);
        (uint256 reserveA, uint256 reserveB,) = route.getPairReserves(address(weth), address(usdc));
        assertEq(amountOut, amountIn * reserveB / reserveA);
        amountOut = route.quote(amountIn, address(usdc), address(weth), 0);
        assertEq(amountOut, amountIn * reserveA / reserveB);
    }

    function testGetOrigin() public {
        (address pair, address origin) = route.getOrigin(address(weth), address(usdc), 0);
        assertEq(pair, address(sushiWethUsdcPool));
        assertEq(origin, address(sushiWethUsdcPool));

        (pair, origin) = route.getOrigin(address(usdc), address(weth), 0);
        assertEq(pair, address(sushiWethUsdcPool));
        assertEq(origin, address(sushiWethUsdcPool));
    }

    function testGetAmountOut1() public {
        uint256 amountIn = 1e18;
        (uint256 amountOut, address pair, uint24 swapFee) = route.getAmountOut(amountIn, address(weth), address(usdc), 0);
        assertEq(swapFee, 3000);
        assertEq(pair, address(sushiWethUsdcPool));
        assertGt(amountOut, 0);

        vm.startPrank(owner);
        uint256 balanceA0 = weth.balanceOf(pair);
        weth.transfer(pair, amountIn);
        uint256 balanceA1 = weth.balanceOf(pair);
        assertEq(amountIn, balanceA1 - balanceA0);

        balanceA0 = weth.balanceOf(owner);
        uint256 balanceB0 = usdc.balanceOf(owner);
        assertGt(balanceB0, 0);
        route.swap(address(weth), address(usdc), 0, address(owner));
        balanceA1 = weth.balanceOf(owner);
        uint256 balanceB1 = usdc.balanceOf(owner);
        assertGt(balanceB1, 0);

        assertEq(0, balanceA1 - balanceA0);
        assertEq(amountOut, balanceB1 - balanceB0);

        vm.stopPrank();
    }

    function testGetAmountOut2() public {
        uint256 amountIn = 1e6;
        (uint256 amountOut, address pair, uint24 swapFee) = route.getAmountOut(amountIn, address(usdc), address(weth), 0);
        assertEq(swapFee, 3000);
        assertEq(pair, address(sushiWethUsdcPool));
        assertGt(amountOut, 0);

        vm.startPrank(owner);
        uint256 balanceA0 = usdc.balanceOf(pair);
        usdc.transfer(pair, amountIn);
        uint256 balanceA1 = usdc.balanceOf(pair);
        assertEq(amountIn, balanceA1 - balanceA0);

        balanceA0 = usdc.balanceOf(owner);
        uint256 balanceB0 = weth.balanceOf(owner);
        assertGt(balanceB0, 0);
        route.swap(address(usdc), address(weth), 0, address(owner));
        balanceA1 = usdc.balanceOf(owner);
        uint256 balanceB1 = weth.balanceOf(owner);
        assertGt(balanceB1, 0);

        assertEq(0, balanceA1 - balanceA0);
        assertEq(amountOut, balanceB1 - balanceB0);

        vm.stopPrank();
    }

    function testGetAmountIn1() public {
        uint256 amountOut = 1e6;
        (uint256 amountIn, address pair, uint24 swapFee) = route.getAmountIn(amountOut, address(weth), address(usdc), 0);
        assertEq(swapFee, 3000);
        assertEq(pair, address(sushiWethUsdcPool));
        assertGt(amountIn, 0);

        vm.startPrank(owner);
        uint256 balanceA0 = weth.balanceOf(pair);
        weth.transfer(pair, amountIn);
        uint256 balanceA1 = weth.balanceOf(pair);
        assertEq(amountIn, balanceA1 - balanceA0);

        balanceA0 = weth.balanceOf(owner);
        uint256 balanceB0 = usdc.balanceOf(owner);
        assertGt(balanceB0, 0);
        route.swap(address(weth), address(usdc), 0, address(owner));
        balanceA1 = weth.balanceOf(owner);
        uint256 balanceB1 = usdc.balanceOf(owner);
        assertGt(balanceB1, 0);

        assertEq(0, balanceA1 - balanceA0);
        assertEq(amountOut, balanceB1 - balanceB0);

        vm.stopPrank();
    }

    function testGetAmountIn2() public {
        uint256 amountOut = 1e18;
        (uint256 amountIn, address pair, uint24 swapFee) = route.getAmountIn(amountOut, address(usdc), address(weth), 0);
        assertEq(swapFee, 3000);
        assertEq(pair, address(sushiWethUsdcPool));
        assertGt(amountIn, 0);

        vm.startPrank(owner);
        uint256 balanceA0 = usdc.balanceOf(pair);
        usdc.transfer(pair, amountIn);
        uint256 balanceA1 = usdc.balanceOf(pair);
        assertEq(amountIn, balanceA1 - balanceA0);

        balanceA0 = usdc.balanceOf(owner);
        uint256 balanceB0 = weth.balanceOf(owner);
        assertGt(balanceB0, 0);
        route.swap(address(usdc), address(weth), 0, address(owner));
        balanceA1 = usdc.balanceOf(owner);
        uint256 balanceB1 = weth.balanceOf(owner);
        assertGt(balanceB1, 0);

        assertEq(0, balanceA1 - balanceA0);
        assertApproxEqRel(amountOut, balanceB1 - balanceB0, 1e8);

        vm.stopPrank();
    }
}