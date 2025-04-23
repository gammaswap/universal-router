// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import '../fixtures/TestBed.sol';
import '../../../contracts/test/TestUniversalRouter.sol';
import '../../../contracts/test/routes/TestAerodromeCL.sol';
import '../../../contracts/interfaces/external/aerodrome-cl/IAeroCLCustomFeeModule.sol';

contract AerodromeCLTest is TestBed {

    address owner;
    TestAerodromeCL route;

    function setUp() public {
        owner = vm.addr(1);
        initSetup(owner);

        route = new TestAerodromeCL(7, address(aeroCLFactory), address(weth));
    }

    function testConstants() public {
        assertEq(route.protocolId(), 7);
        assertEq(route.factory(), address(aeroCLFactory));
        assertEq(route.WETH(), address(weth));
    }

    function testPairFor() public {
        address pair = route.getPairFor(address(usdc), address(weth), aeroCLTickSpacing);
        assertEq(pair, address(aeroCLWethUsdcPool));

        pair = route.getPairFor(address(weth), address(usdc), aeroCLTickSpacing);
        assertEq(pair, address(aeroCLWethUsdcPool));
    }

    function testPairForErrors() public {
        vm.expectRevert("AeroPoolAddress: INVALID_ORDER");
        route.getPairFor(address(weth), address(weth), aeroCLTickSpacing);

        vm.expectRevert("AerodromeCL: AMM_DOES_NOT_EXIST");
        route.getPairFor(address(weth), address(vm.addr(123456)), aeroCLTickSpacing);
    }

    function testDecodePrice() public {
        (uint256 sqrtPriceX96,,,,,) = aeroCLWethUsdcPool.slot0();
        uint8 decimals = GammaSwapLibrary.decimals(aeroCLWethUsdcPool.token0());
        uint256 price = route.getDecodedPrice(sqrtPriceX96,10**decimals);
        assertApproxEqRel(price,2999999999,1e14);
    }

    function testQuote() public {
        uint256 amountIn = 1e18;
        uint256 amountOut = route.quote(amountIn, address(weth), address(usdc), uint24(aeroCLTickSpacing));

        (uint256 sqrtPriceX96,,,,,) = aeroCLWethUsdcPool.slot0();
        uint8 decimals = GammaSwapLibrary.decimals(aeroCLWethUsdcPool.token0());
        uint256 price = route.getDecodedPrice(sqrtPriceX96,10**decimals);
        assertEq(amountOut, amountIn * price / (10**decimals));

        amountIn = 1e6;
        amountOut = route.quote(amountIn, address(usdc), address(weth), uint24(aeroCLTickSpacing));

        (sqrtPriceX96,,,,,) = aeroCLWethUsdcPool.slot0();
        decimals = GammaSwapLibrary.decimals(aeroCLWethUsdcPool.token0());
        price = route.getDecodedPrice(sqrtPriceX96,10**decimals);
        assertEq(amountOut, amountIn * (10**decimals) / price);
    }

    function testFee1() public {
        vm.expectRevert("AerodromeCL: AMM_DOES_NOT_EXIST");
        uint256 fee = route.getFee(address(weth), address(usdc), poolFee1);

        fee = route.getFee(address(weth), address(usdc), 100);
        assertEq(fee, 500);

        fee = route.getFee(address(usdc), address(weth), 100);
        assertEq(fee, 500);

        (address pair,,) = route.pairFor(address(usdc), address(weth), 100);

        vm.startPrank(owner);

        IAeroCLCustomFeeModule(aeroCLFactory.swapFeeModule()).setCustomFee(pair, uint24(3000));

        fee = route.getFee(address(weth), address(usdc), 100);
        assertEq(fee, 3000);

        fee = route.getFee(address(weth), address(usdc), 100);
        assertEq(fee, 3000);

        vm.stopPrank();
    }

    function testGetOrigin() public {
        (address pair, address origin) = route.getOrigin(address(weth), address(usdc), uint24(aeroCLTickSpacing));
        assertEq(pair, address(aeroCLWethUsdcPool));
        assertEq(origin, address(route));

        (pair, origin) = route.getOrigin(address(usdc), address(weth), uint24(aeroCLTickSpacing));
        assertEq(pair, address(aeroCLWethUsdcPool));
        assertEq(origin, address(route));
    }

    function testGetAmountOut1() public {
        uint256 amountIn = 1e18;
        (uint256 amountOut, address pair, uint24 swapFee) = route.getAmountOut(amountIn, address(weth), address(usdc), uint24(aeroCLTickSpacing));
        assertEq(swapFee, uint24(aeroCLTickSpacing));
        assertEq(pair, address(aeroCLWethUsdcPool));
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
        (uint256 amountOut, address pair, uint24 swapFee) = route.getAmountOut(amountIn, address(usdc), address(weth), uint24(aeroCLTickSpacing));
        assertEq(swapFee, uint24(aeroCLTickSpacing));
        assertEq(pair, address(aeroCLWethUsdcPool));
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

    function testGetAmountOutNoSwap1() public {
        (uint256 amountOut, address pair, uint24 swapFee) = route.getAmountOutNoSwap(0, address(weth), address(usdc), uint24(aeroCLTickSpacing));
        assertEq(swapFee, uint24(aeroCLTickSpacing));
        assertEq(pair, address(aeroCLWethUsdcPool));
        assertEq(amountOut, 0);
    }

    function testGetAmountOutNoSwap2() public {
        (uint256 amountOut, address pair, uint24 swapFee) = route.getAmountOutNoSwap(0, address(usdc), address(weth), uint24(aeroCLTickSpacing));
        assertEq(swapFee, uint24(aeroCLTickSpacing));
        assertEq(pair, address(aeroCLWethUsdcPool));
        assertEq(amountOut, 0);
    }

    function testGetAmountIn1() public {
        uint256 amountOut = 1e6;
        (uint256 amountIn, address pair, uint24 swapFee) = route.getAmountIn(amountOut, address(weth), address(usdc), uint24(aeroCLTickSpacing));
        assertEq(swapFee, uint24(aeroCLTickSpacing));
        assertEq(pair, address(aeroCLWethUsdcPool));
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
        (uint256 amountIn, address pair, uint24 swapFee) = route.getAmountIn(amountOut, address(usdc), address(weth), uint24(aeroCLTickSpacing));
        assertEq(swapFee, uint24(aeroCLTickSpacing));
        assertEq(pair, address(aeroCLWethUsdcPool));
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
