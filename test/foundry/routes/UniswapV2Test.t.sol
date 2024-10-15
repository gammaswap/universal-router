// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "../fixtures/TestBed.sol";
import "../../../contracts/test/TestUniversalRouter.sol";
import "../../../contracts/test/routes/TestUniswapV2.sol";

contract UniswapV2Test is TestBed {

    address owner;
    TestUniswapV2 route;

    function setUp() public {
        owner = vm.addr(1);
        initSetup(owner);

        route = new TestUniswapV2(1, address(uniFactory), address(weth));
    }

    function testConstants() public {
        assertEq(route.protocolId(), 1);
        assertEq(route.factory(), address(uniFactory));
        assertEq(route.WETH(), address(weth));
        assertEq(route.getInitCodeHash(),0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f);
    }

    function testPairFor() public {
        (address pair, address token0, address token1) = route.getPairFor(address(usdc), address(weth));
        assertEq(pair, address(wethUsdcPool));
        if(address(usdc) < address(weth)) {
            assertEq(token0, address(usdc));
            assertEq(token1, address(weth));
        } else {
            assertEq(token1, address(usdc));
            assertEq(token0, address(weth));
        }

        (pair, token0, token1) = route.getPairFor(address(weth), address(usdc));
        assertEq(pair, address(wethUsdcPool));
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

    function createBytes(address tokenIn, address tokenOut, uint24 fee, uint16 protocolId) internal pure returns (bytes memory) {
        return abi.encodePacked(tokenIn, protocolId, fee, tokenOut);
    }
}