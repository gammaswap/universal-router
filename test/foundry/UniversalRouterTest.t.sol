// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "./fixtures/TestBed.sol";
import "../../contracts/UniversalRouter.sol";

contract UniversalRouterTest is TestBed {

    UniversalRouter router;
    address owner;

    function setUp() public {
        owner = vm.addr(1);
        initSetup(owner);
        router = new UniversalRouter(address(uniFactory));
    }

    function createBytes(
        address addr1,
        address addr2,
        uint24 uint24Value,
        uint16 uint16Value
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(addr1, uint16Value, uint24Value, addr2);
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
