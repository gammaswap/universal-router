// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import '../fixtures/TestBed.sol';
import '../../../contracts/test/TestUniversalRouter.sol';
import '../../../contracts/test/routes/TestAerodrome.sol';

contract AerodromeTestStable is TestBed {

    address owner;
    TestAerodrome route;

    function setUp() public {
        owner = vm.addr(1);
        initSetup(owner);

        route = new TestAerodrome(5, address(aeroFactory), true, address(weth));
    }

    function testConstants() public {
        assertEq(route.protocolId(), 5);
        assertEq(route.factory(), address(aeroFactory));
        assertEq(route.WETH(), address(weth));
        assertEq(route.implementation(), IAeroPoolFactory(aeroFactory).implementation());
        assertEq(route.isStable(), true);
    }

    function testPairFor() public {
        (address pair, address token0, address token1) = route.getPairFor(address(usdc), address(usdt));
        assertEq(pair, address(aeroUsdtUsdcPool));
        if(address(usdc) < address(usdt)) {
            assertEq(token0, address(usdc));
            assertEq(token1, address(usdt));
        } else {
            assertEq(token1, address(usdc));
            assertEq(token0, address(usdt));
        }

        (pair, token0, token1) = route.getPairFor(address(usdt), address(usdc));
        assertEq(pair, address(aeroUsdtUsdcPool));
        if(address(usdc) < address(usdt)) {
            assertEq(token0, address(usdc));
            assertEq(token1, address(usdt));
        } else {
            assertEq(token1, address(usdc));
            assertEq(token0, address(usdt));
        }
    }

    function testPairForErrors() public {
        vm.expectRevert('CPMMRoute: IDENTICAL_ADDRESSES');
        route.getPairFor(address(usdc), address(usdc));

        vm.expectRevert('Aerodrome: AMM_DOES_NOT_EXIST');
        route.getPairFor(address(usdc), address(vm.addr(123456)));
    }

    function testGetReserves() public {
        (uint256 reserveA0, uint256 reserveB0, address pair0) = route.getPairReserves(address(dai), address(usdc));
        assertEq(pair0, address(aeroDaiUsdcPool));
        assertGt(reserveA0, 0);
        assertGt(reserveB0, 0);
        assertNotEq(reserveA0, reserveB0);
        (uint256 reserveA1, uint256 reserveB1, address pair1) = route.getPairReserves(address(usdc), address(dai));
        assertEq(pair1, address(aeroDaiUsdcPool));
        assertEq(reserveA0, reserveB1);
        assertEq(reserveB0, reserveA1);
    }

    function testQuote() public {
        uint256 amountIn = 1e18;
        uint256 amountOut = route.quote(amountIn, address(dai), address(usdc), 0);
        (uint256 reserveA, uint256 reserveB,) = route.getPairReserves(address(dai), address(usdc));
        assertEq(amountOut, amountIn * reserveB / reserveA);
        amountOut = route.quote(amountIn, address(usdc), address(dai), 0);
        assertEq(amountOut, amountIn * reserveA / reserveB);
    }

    function testFee() public {
        vm.expectRevert("Aerodrome: AMM_DOES_NOT_EXIST");
        uint256 fee = route.getFee(address(weth), address(usdc), poolFee1);

        fee = route.getFee(address(dai), address(usdc), 100);
        assertEq(fee, 500);

        fee = route.getFee(address(dai), address(usdc), 2000);
        assertEq(fee, 500);

        fee = route.getFee(address(usdt), address(usdc), 100);
        assertEq(fee, 500);

        fee = route.getFee(address(usdt), address(dai), 3000);
        assertEq(fee, 500);

        fee = route.getFee(address(usdt), address(dai), 500);
        assertEq(fee, 500);

        aeroFactory.setFee(true, 300);

        fee = route.getFee(address(dai), address(usdc), 100);
        assertEq(fee, 30000);

        fee = route.getFee(address(dai), address(usdc), 2000);
        assertEq(fee, 30000);

        fee = route.getFee(address(usdt), address(usdc), 100);
        assertEq(fee, 30000);

        fee = route.getFee(address(usdt), address(dai), 3000);
        assertEq(fee, 30000);

        fee = route.getFee(address(usdt), address(dai), 500);
        assertEq(fee, 30000);

        fee = route.getFee(address(usdt), address(dai), 300);
        assertEq(fee, 30000);

        (address pair,,) = route.pairFor(address(usdt), address(usdc), 300);

        aeroFactory.setCustomFee(pair, 20);

        aeroFactory.setFee(true, 200);

        fee = route.getFee(address(dai), address(usdc), 100);
        assertEq(fee, 20000);

        fee = route.getFee(address(dai), address(usdc), 2000);
        assertEq(fee, 20000);

        fee = route.getFee(address(usdt), address(usdc), 100);
        assertEq(fee, 2000);

        fee = route.getFee(address(usdt), address(dai), 3000);
        assertEq(fee, 20000);

        fee = route.getFee(address(usdt), address(dai), 500);
        assertEq(fee, 20000);

        fee = route.getFee(address(usdt), address(dai), 300);
        assertEq(fee, 20000);
    }

    function testGetOrigin() public {
        (address pair, address origin) = route.getOrigin(address(usdt), address(usdc), 0);
        assertEq(pair, address(aeroUsdtUsdcPool));
        assertEq(origin, address(aeroUsdtUsdcPool));

        (pair, origin) = route.getOrigin(address(usdc), address(usdt), 0);
        assertEq(pair, address(aeroUsdtUsdcPool));
        assertEq(origin, address(aeroUsdtUsdcPool));
    }

    function testGetAmountOut1() public {
        uint256 amountIn = 1e18;
        (uint256 amountOut, address pair, uint24 swapFee) = route.getAmountOut(amountIn, address(dai), address(usdc), 0);
        assertEq(swapFee, 5);
        assertEq(pair, address(aeroDaiUsdcPool));
        assertGt(amountOut, 0);

        vm.startPrank(owner);
        uint256 balanceA0 = dai.balanceOf(pair);
        dai.transfer(pair, amountIn);
        uint256 balanceA1 = dai.balanceOf(pair);
        assertEq(amountIn, balanceA1 - balanceA0);

        balanceA0 = dai.balanceOf(owner);
        uint256 balanceB0 = usdc.balanceOf(owner);
        assertGt(balanceB0, 0);
        route.swap(address(dai), address(usdc), 0, address(owner));
        balanceA1 = dai.balanceOf(owner);
        uint256 balanceB1 = usdc.balanceOf(owner);
        assertGt(balanceB1, 0);

        assertEq(0, balanceA1 - balanceA0);
        assertEq(amountOut, balanceB1 - balanceB0);

        vm.stopPrank();
    }

    function testGetAmountOut2() public {
        uint256 amountIn = 1e6;
        (uint256 amountOut, address pair, uint24 swapFee) = route.getAmountOut(amountIn, address(usdc), address(dai), 0);
        assertEq(swapFee, 5);
        assertEq(pair, address(aeroDaiUsdcPool));
        assertGt(amountOut, 0);

        vm.startPrank(owner);
        uint256 balanceA0 = usdc.balanceOf(pair);
        usdc.transfer(pair, amountIn);
        uint256 balanceA1 = usdc.balanceOf(pair);
        assertEq(amountIn, balanceA1 - balanceA0);

        balanceA0 = usdc.balanceOf(owner);
        uint256 balanceB0 = dai.balanceOf(owner);
        assertGt(balanceB0, 0);
        route.swap(address(usdc), address(dai), 0, address(owner));
        balanceA1 = usdc.balanceOf(owner);
        uint256 balanceB1 = dai.balanceOf(owner);
        assertGt(balanceB1, 0);

        assertEq(0, balanceA1 - balanceA0);
        assertEq(amountOut, balanceB1 - balanceB0);

        vm.stopPrank();
    }

    function testGetAmountOutNoSwap1() public {
        (uint256 amountOut, address pair, uint24 swapFee) = route.getAmountOutNoSwap(0, address(dai), address(usdc), 0);
        assertEq(swapFee, 5);
        assertEq(pair, address(aeroDaiUsdcPool));
        assertEq(amountOut, 0);
    }

    function testGetAmountOutNoSwap2() public {
        (uint256 amountOut, address pair, uint24 swapFee) = route.getAmountOutNoSwap(0, address(usdc), address(dai), 0);
        assertEq(swapFee, 5);
        assertEq(pair, address(aeroDaiUsdcPool));
        assertEq(amountOut, 0);
    }

    function testGetAmountIn1() public {
        uint256 amountOut = 1e6;
        (uint256 amountIn, address pair, uint24 swapFee) = route.getAmountIn(amountOut, address(dai), address(usdc), 0);
        assertEq(swapFee, 5);
        assertEq(pair, address(aeroDaiUsdcPool));
        assertGt(amountIn, 0);

        vm.startPrank(owner);
        uint256 balanceA0 = dai.balanceOf(pair);
        dai.transfer(pair, amountIn);
        uint256 balanceA1 = dai.balanceOf(pair);
        assertEq(amountIn, balanceA1 - balanceA0);

        balanceA0 = dai.balanceOf(owner);
        uint256 balanceB0 = usdc.balanceOf(owner);
        assertGt(balanceB0, 0);
        route.swap(address(dai), address(usdc), 0, address(owner));
        balanceA1 = dai.balanceOf(owner);
        uint256 balanceB1 = usdc.balanceOf(owner);
        assertGt(balanceB1, 0);

        assertEq(0, balanceA1 - balanceA0);
        assertEq(amountOut, balanceB1 - balanceB0);

        vm.stopPrank();
    }

    function testGetAmountIn2() public {
        uint256 amountOut = 1e18;
        (uint256 amountIn, address pair, uint24 swapFee) = route.getAmountIn(amountOut, address(usdc), address(dai), 0);
        assertEq(swapFee, 5);
        assertEq(pair, address(aeroDaiUsdcPool));
        assertGt(amountIn, 0);

        vm.startPrank(owner);
        uint256 balanceA0 = usdc.balanceOf(pair);
        usdc.transfer(pair, amountIn);
        uint256 balanceA1 = usdc.balanceOf(pair);
        assertEq(amountIn, balanceA1 - balanceA0);

        balanceA0 = usdc.balanceOf(owner);
        uint256 balanceB0 = dai.balanceOf(owner);
        assertGt(balanceB0, 0);
        route.swap(address(usdc), address(dai), 0, address(owner));
        balanceA1 = usdc.balanceOf(owner);
        uint256 balanceB1 = dai.balanceOf(owner);
        assertGt(balanceB1, 0);

        assertEq(0, balanceA1 - balanceA0);
        assertApproxEqRel(amountOut, balanceB1 - balanceB0, 1e12);

        vm.stopPrank();
    }
}