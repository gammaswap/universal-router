// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./fixtures/TestBed.sol";
import "../../contracts/test/TestUniversalRouter.sol";
import "../../contracts/routes/UniswapV2.sol";

contract UniversalRouterTest is TestBed {

    address owner;

    TestUniversalRouter router;
    UniswapV2 uniV2Route;

    function setUp() public {
        owner = vm.addr(1);
        initSetup(owner);
        router = new TestUniversalRouter(address(weth));

        uniV2Route = new UniswapV2(1, address(uniFactory), address(weth));

        // set up routes
        router.addProtocol(1, address(uniV2Route));
    }

    function createBytes(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint16 protocolId
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(tokenIn, protocolId, fee, tokenOut);
    }

    function testThisFunc2() public {
        bytes memory val = createBytes(address(weth), address(usdc), 5, 1);
        console.logBytes(val);
        router.getAmountsOut(1e18, val);
    }

    function testThisFunc3() public {
        //bytes memory val = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab1';
        //bytes memory val = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e5831';
        //bytes memory val = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e5831000100010076991314cEE341ebE37e6E2712cb04F5d56dE355';
        bytes memory val = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e5831000100010076991314cEE341ebE37e6E2712cb04F5d56dE3550001000100F6D9C101ceeA72655A13a8Cf1C88c1949Ed399bc';
        address res = router._getTokenOut(val);
        console.log("res:",res);
        /**router.getAmountsOut(1,val);
        console.log("done2");/**/
    }
}
