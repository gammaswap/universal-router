// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import '../fixtures/TestBed.sol';
import '../../../contracts/test/TestUniversalRouter.sol';
import '../../../contracts/test/routes/TestUniswapV3.sol';

contract UniswapV3Test is TestBed {

    address owner;
    TestUniswapV3 route;

    function setUp() public {
        owner = vm.addr(1);
        initSetup(owner);

        route = new TestUniswapV3(6, address(uniFactoryV3), address(weth));
    }

    function testConstants() public {
        assertEq(route.protocolId(), 6);
        assertEq(route.factory(), address(uniFactoryV3));
        assertEq(route.WETH(), address(weth));
        assertEq(route.getInitCodeHash(),0xe34f199b19b2b4f47f68442619d555527d244f78a3297ea89325f843f87b8b54);
    }

    function testPairFor() public {
        address pair = route.getPairFor(address(usdc), address(weth), poolFee1);
        assertEq(pair, address(wethUsdcPoolV3));

        pair = route.getPairFor(address(weth), address(usdc), poolFee1);
        assertEq(pair, address(wethUsdcPoolV3));
    }

    function testPairForErrors() public {
        vm.expectRevert('PoolAddress: INVALID_ORDER');
        route.getPairFor(address(weth), address(weth), poolFee1);

        vm.expectRevert('UniswapV3: AMM_DOES_NOT_EXIST');
        route.getPairFor(address(weth), address(vm.addr(123456)), poolFee1);
    }

    function testDecodePrice() public {
        (uint256 sqrtPriceX96,,,,,,) = wethUsdcPoolV3.slot0();
        uint8 decimals = GammaSwapLibrary.decimals(wethUsdcPoolV3.token0());
        uint256 price = route.getDecodedPrice(sqrtPriceX96,10**decimals);
        assertApproxEqRel(price,2999999999,1e14);
    }

    function testQuote() public {
        uint256 amountIn = 1e18;
        uint256 amountOut = route.quote(amountIn, address(weth), address(usdc), poolFee1);

        (uint256 sqrtPriceX96,,,,,,) = wethUsdcPoolV3.slot0();
        uint8 decimals = GammaSwapLibrary.decimals(wethUsdcPoolV3.token0());
        uint256 price = route.getDecodedPrice(sqrtPriceX96,10**decimals);
        assertEq(amountOut, amountIn * price / (10**decimals));

        amountIn = 1e6;
        amountOut = route.quote(amountIn, address(usdc), address(weth), poolFee1);

        (sqrtPriceX96,,,,,,) = wethUsdcPoolV3.slot0();
        decimals = GammaSwapLibrary.decimals(wethUsdcPoolV3.token0());
        price = route.getDecodedPrice(sqrtPriceX96,10**decimals);
        assertEq(amountOut, amountIn * (10**decimals) / price);
    }

    function testGetOrigin() public {
        (address pair, address origin) = route.getOrigin(address(weth), address(usdc), poolFee1);
        assertEq(pair, address(wethUsdcPoolV3));
        assertEq(origin, address(route));

        (pair, origin) = route.getOrigin(address(usdc), address(weth), poolFee1);
        assertEq(pair, address(wethUsdcPoolV3));
        assertEq(origin, address(route));
    }

    function testGetAmountOut1() public {
        uint256 amountIn = 1e18;
        (uint256 amountOut, address pair, uint24 swapFee) = route.getAmountOut(amountIn, address(weth), address(usdc), poolFee1);
        assertEq(swapFee, poolFee1);
        assertEq(pair, address(wethUsdcPoolV3));
        assertGt(amountOut, 0);

        vm.startPrank(owner);
        uint256 balanceA0 = weth.balanceOf(address(route));
        weth.transfer(address(route), amountIn);
        uint256 balanceA1 = weth.balanceOf(address(route));
        assertEq(amountIn, balanceA1 - balanceA0);

        balanceA0 = weth.balanceOf(owner);
        uint256 balanceB0 = usdc.balanceOf(owner);
        assertGt(balanceB0, 0);
        route.swap(address(weth), address(usdc), swapFee, address(owner));
        balanceA1 = weth.balanceOf(owner);
        uint256 balanceB1 = usdc.balanceOf(owner);
        assertGt(balanceB1, 0);

        assertEq(0, balanceA1 - balanceA0);
        assertEq(amountOut, balanceB1 - balanceB0);

        vm.stopPrank();
    }

    function testGetAmountOut2() public {
        uint256 amountIn = 1e6;
        (uint256 amountOut, address pair, uint24 swapFee) = route.getAmountOut(amountIn, address(usdc), address(weth), poolFee1);
        assertEq(swapFee, poolFee1);
        assertEq(pair, address(wethUsdcPoolV3));
        assertGt(amountOut, 0);

        vm.startPrank(owner);
        uint256 balanceA0 = usdc.balanceOf(address(route));
        usdc.transfer(address(route), amountIn);
        uint256 balanceA1 = usdc.balanceOf(address(route));
        assertEq(amountIn, balanceA1 - balanceA0);

        balanceA0 = usdc.balanceOf(owner);
        uint256 balanceB0 = weth.balanceOf(owner);
        assertGt(balanceB0, 0);
        route.swap(address(usdc), address(weth), swapFee, address(owner));
        balanceA1 = usdc.balanceOf(owner);
        uint256 balanceB1 = weth.balanceOf(owner);
        assertGt(balanceB1, 0);

        assertEq(0, balanceA1 - balanceA0);
        assertEq(amountOut, balanceB1 - balanceB0);

        vm.stopPrank();
    }

    function testGetAmountIn1() public {
        uint256 amountOut = 1e6;
        (uint256 amountIn, address pair, uint24 swapFee) = route.getAmountIn(amountOut, address(weth), address(usdc), poolFee1);
        assertEq(swapFee, poolFee1);
        assertEq(pair, address(wethUsdcPoolV3));
        assertGt(amountIn, 0);

        vm.startPrank(owner);
        uint256 balanceA0 = weth.balanceOf(address(route));
        weth.transfer(address(route), amountIn);
        uint256 balanceA1 = weth.balanceOf(address(route));
        assertEq(amountIn, balanceA1 - balanceA0);

        balanceA0 = weth.balanceOf(owner);
        uint256 balanceB0 = usdc.balanceOf(owner);
        assertGt(balanceB0, 0);
        route.swap(address(weth), address(usdc), swapFee, address(owner));
        balanceA1 = weth.balanceOf(owner);
        uint256 balanceB1 = usdc.balanceOf(owner);
        assertGt(balanceB1, 0);

        assertEq(0, balanceA1 - balanceA0);
        assertEq(amountOut, balanceB1 - balanceB0);

        vm.stopPrank();
    }

    function testGetAmountIn2() public {
        uint256 amountOut = 1e18;
        (uint256 amountIn, address pair, uint24 swapFee) = route.getAmountIn(amountOut, address(usdc), address(weth), poolFee1);
        assertEq(swapFee, poolFee1);
        assertEq(pair, address(wethUsdcPoolV3));
        assertGt(amountIn, 0);

        vm.startPrank(owner);
        uint256 balanceA0 = usdc.balanceOf(address(route));
        usdc.transfer(address(route), amountIn);
        uint256 balanceA1 = usdc.balanceOf(address(route));
        assertEq(amountIn, balanceA1 - balanceA0);

        balanceA0 = usdc.balanceOf(owner);
        uint256 balanceB0 = weth.balanceOf(owner);
        assertGt(balanceB0, 0);
        route.swap(address(usdc), address(weth), swapFee, address(owner));
        balanceA1 = usdc.balanceOf(owner);
        uint256 balanceB1 = weth.balanceOf(owner);
        assertGt(balanceB1, 0);

        assertEq(0, balanceA1 - balanceA0);
        assertApproxEqRel(amountOut, balanceB1 - balanceB0, 1e10);

        vm.stopPrank();
    }
}
