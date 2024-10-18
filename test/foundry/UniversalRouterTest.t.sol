// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "./fixtures/TestBed.sol";
import "./utils/Random.sol";
import "../../contracts/routes/UniswapV2.sol";
import "../../contracts/routes/SushiswapV2.sol";
import "../../contracts/routes/DeltaSwap.sol";
import "../../contracts/routes/Aerodrome.sol";
import "../../contracts/routes/UniswapV3.sol";
import "../../contracts/interfaces/IUniversalRouter.sol";

contract UniversalRouterTest is TestBed {

    address owner;
    UniswapV2 uniV2Route;
    SushiswapV2 sushiV2Route;
    DeltaSwap dsRoute;
    Aerodrome aeroRoute;
    Aerodrome aeroStableRoute;
    UniswapV3 uniV3Route;
    Random random;
    address[] tokens;

    uint256 constant PROTOCOL_ROUTES_COUNT = 6;

    function setUp() public {
        random = new Random();
        owner = vm.addr(1);
        initSetup(owner);

        tokens = new address[](5);
        tokens[0] = address(weth);
        tokens[1] = address(usdc);
        tokens[2] = address(usdt);
        tokens[3] = address(dai);
        tokens[4] = address(wbtc);

        uniV2Route = new UniswapV2(1, address(uniFactory), address(weth));
        sushiV2Route = new SushiswapV2(2, address(sushiFactory), address(weth));
        dsRoute = new DeltaSwap(3, address(dsFactory), address(weth));
        aeroRoute = new Aerodrome(4, address(aeroFactory), false, address(weth));
        aeroStableRoute = new Aerodrome(5, address(aeroFactory), true, address(weth));
        uniV3Route = new UniswapV3(6, address(uniFactoryV3), address(weth));

        // set up routes
        router.addProtocol(address(uniV2Route));
        router.addProtocol(address(sushiV2Route));
        router.addProtocol(address(dsRoute));
        router.addProtocol(address(aeroRoute));
        router.addProtocol(address(aeroStableRoute));
        router.addProtocol(address(uniV3Route));
    }

    function createBytes(
        address tokenIn,
        address tokenOut,
        uint24 fee,
        uint16 protocolId
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(tokenIn, protocolId, fee, tokenOut);
    }

    function testAddRemoveProtocol() public {
        vm.expectRevert("ZERO_ADDRESS");
        router.addProtocol(address(0));

        UniswapV2 route0 = new UniswapV2(0, address(uniFactory), address(weth));
        vm.expectRevert("INVALID_PROTOCOL_ID");
        router.addProtocol(address(route0));

        UniswapV2 route2 = new UniswapV2(20, address(uniFactory), address(weth));

        assertEq(router.protocols(20),address(0));

        assertEq(router.owner(), address(this));

        address userX = vm.addr(12345);
        vm.prank(userX);
        vm.expectRevert("Ownable: caller is not the owner");
        router.addProtocol(address(route2));

        router.addProtocol(address(route2));
        assertEq(router.protocols(20),address(route2));

        UniswapV2 route2a = new UniswapV2(20, address(uniFactory), address(weth));
        vm.expectRevert("PROTOCOL_ID_USED");
        router.addProtocol(address(route2a));

        vm.prank(userX);
        vm.expectRevert("Ownable: caller is not the owner");
        router.removeProtocol(0);

        vm.expectRevert("INVALID_PROTOCOL_ID");
        router.removeProtocol(0);

        vm.expectRevert("PROTOCOL_ID_UNUSED");
        router.removeProtocol(30);

        router.removeProtocol(20);
        assertEq(router.protocols(20),address(0));
    }

    function testQuotes(uint8 tokenChoices, uint128 seed, uint256 amountIn) public {
        bytes memory path = createPath(tokenChoices, seed);
        uint256 minAmountOut;
        (amountIn, minAmountOut) = calcMinAmount(amountIn, path);
        uint256 amountOut = router.quote(amountIn, path);
        assertGt(amountOut,minAmountOut);
    }

    function testGetAmountsOut(uint8 tokenChoices, uint128 seed, uint256 amountIn) public {
        bytes memory path = createPath(tokenChoices, seed);
        IUniversalRouter.Route[] memory _routes = router.calcRoutes(path, address(this));
        uint256 minAmountOut;
        (amountIn, minAmountOut) = calcMinAmount(amountIn, path);
        (uint256[] memory amounts, IUniversalRouter.Route[] memory routes) = router.getAmountsOut(amountIn, path);
        assertEq(routes.length, _routes.length);
        assertEq(routes.length, amounts.length - 1);
        for(uint256 i = 0; i < _routes.length; i++) {
            assertEq(routes[i].from,_routes[i].from);
            assertEq(routes[i].to,_routes[i].to);
            assertEq(routes[i].pair,_routes[i].pair);
            assertEq(routes[i].protocolId,_routes[i].protocolId);
            if(routes[i].protocolId == 6) {
                assertEq(routes[i].fee,_routes[i].fee);
            }
            assertEq(routes[i].origin,address(0));
            assertEq(routes[i].destination,address(0));
            assertEq(routes[i].hop,_routes[i].hop);
        }
        assertEq(amounts[0], amountIn);
        for(uint256 i = 0; i < amounts.length; i++) {
            assertGt(amounts[i],0);
        }
        assertGt(amounts[amounts.length - 1], minAmountOut);
    }

    function calcMinAmount(uint256 amountIn, bytes memory path) internal view returns(uint256, uint256) {
        IUniversalRouter.Route[] memory routes = router.calcRoutes(path, address(router));
        uint256 minAmountOut;
        if(routes[0].from == address(weth)) {
            amountIn = bound(amountIn, 1e18, 10e18);
            if(routes[routes.length-1].to == address(wbtc)) {
                minAmountOut = 4400384;
            } else if(routes[routes.length-1].to == address(dai)) {
                minAmountOut = 2800e18;
            } else {
                minAmountOut = 2800e6;
            }
        } else if(routes[0].from == address(wbtc)) {
            amountIn = bound(amountIn, 1e6, 1e8);
            if(routes[routes.length-1].to == address(weth)) {
                minAmountOut = 2e17;
            } else if(routes[routes.length-1].to == address(dai)) {
                minAmountOut = 620e18;
            } else {
                minAmountOut = 620e6;
            }
        } else if(routes[0].from == address(dai)) {
            amountIn = bound(amountIn, 1e18, 1000e18);
            if(routes[routes.length-1].to == address(weth)) {
                minAmountOut = 323333333333333;
            } else if(routes[routes.length-1].to == address(wbtc)) {
                minAmountOut = 1500;
            } else {
                minAmountOut = 9e5;
            }
        } else {
            amountIn = bound(amountIn, 1e6, 1000e6);
            if(routes[routes.length-1].to == address(weth)) {
                minAmountOut = 323333333333333;
            } else if(routes[routes.length-1].to == address(wbtc)) {
                minAmountOut = 1500;
            } else if(routes[routes.length-1].to == address(dai)) {
                minAmountOut = 9e17;
            } else {
                minAmountOut = 9e5;
            }
        }
        return (amountIn, minAmountOut);
    }

    function testCalcRoutes(uint8 tokenChoices, uint128 seed) public {
        bytes memory path = createPath(tokenChoices, seed);
        address to = vm.addr(0x123);
        IUniversalRouter.Route[] memory routes = router.calcRoutes(path, to);
        for(uint256 i = 0; i < routes.length; i++) {
            address pair = getPair(routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee);
            assertTrue(pair != address(0));
            assertTrue(validateTokens(routes[i].from, routes[i].to, pair));
            assertEq(routes[i].hop, router.protocols(routes[i].protocolId));
            assertEq(routes[i].pair, pair);
            if(routes[i].protocolId == 6) {
                assertEq(routes[i].origin, router.protocols(routes[i].protocolId));
            } else {
                assertEq(routes[i].origin, pair);
            }
            if(i == routes.length - 1) {
                assertEq(routes[i].destination, to);
            } else {
                assertEq(routes[i].destination, routes[i + 1].origin);
                assertEq(routes[i].to, routes[i + 1].from);
            }
        }
    }

    function validateTokens(address from, address to, address pair) internal view returns (bool) {
        bool isForward = ICPMM(pair).token0() == from || ICPMM(pair).token1() == to;
        bool isBackward = ICPMM(pair).token1() == from || ICPMM(pair).token0() == to;
        return (isForward && !isBackward) || (!isForward && isBackward);
    }

    function getPair(address from, address to, uint16 protocolId, uint24 fee) internal view returns(address) {
        if(protocolId == 1) {
            return uniFactory.getPair(from, to);
        } else if(protocolId == 2) {
            return sushiFactory.getPair(from, to);
        } else if(protocolId == 3) {
            return dsFactory.getPair(from, to);
        } else if(protocolId == 4) {
            return aeroFactory.getPool(from, to, false);
        } else if(protocolId == 5) {
            return aeroFactory.getPool(from, to, true);
        } else if(protocolId == 6) {
            return uniFactoryV3.getPool(from, to, fee);
        }
        return address(0);
    }

    function createPath(uint8 tokenChoices, uint128 seed) internal view returns(bytes memory) {
        address[] memory _tokens = tokens;
        _tokens = random.shuffleAddresses(_tokens, seed);
        _tokens = getTokens(tokenChoices, _tokens);

        bytes memory _path = abi.encodePacked(_tokens[0]);

        for(uint256 i = 1; i < _tokens.length; i++) {
            uint16 protocolId = uint16(random.getRandomNumber(PROTOCOL_ROUTES_COUNT, seed + i + 10) + 1);
            if(protocolId == 4) {
                if(isStable(_tokens[i-1], _tokens[i])) {
                    protocolId = 5;
                }
            } else if(protocolId == 5) {
                if(!isStable(_tokens[i-1], _tokens[i])) {
                    protocolId = 4;
                }
            }
            uint24 fee = protocolId == 6 ? poolFee1 : 0;
            _path = abi.encodePacked(_path, protocolId, fee, _tokens[i]);
        }
        return _path;
    }

    function isStable(address token0, address token1) internal view returns(bool) {
        return (token0 == address(usdc) && token1 == address(usdt))
            || (token1 == address(usdc) && token0 == address(usdt))
            || (token0 == address(usdc) && token1 == address(dai))
            || (token1 == address(usdc) && token0 == address(dai))
            || (token0 == address(usdt) && token1 == address(dai))
            || (token1 == address(usdt) && token0 == address(dai));
    }

    function getTokens(uint8 tokenChoices, address[] memory _tokens) internal pure returns (address[] memory) {
        // Count the number of set bits to allocate the output array size
        uint8 count = 0;
        uint8 mask = 0x1F; // Mask for the first 5 bits (0b00011111)
        uint8 maskedChoices = tokenChoices & mask;

        for (uint8 i = 0; i < 5; i++) {
            if (maskedChoices & (uint8(1) << i) != 0) {
                count++;
            }
        }

        // If fewer than 2 bits are set, set additional bits
        if (count < 2) {
            // Set the missing bits to ensure at least 2 bits are set
            for (uint8 i = 0; i < 5 && count < 2; i++) {
                if (maskedChoices & (uint8(1) << i) == 0) {
                    maskedChoices |= (uint8(1) << i); // Set the bit
                    count++;
                }
            }
        }

        // Initialize the result array with size of `count`
        address[] memory selectedTokens = new address[](count);
        uint8 index = 0;

        // Collect values from tokens array where bits are set
        for (uint8 i = 0; i < 5; i++) {
            if (maskedChoices & (uint8(1) << i) != 0) {
                selectedTokens[index] = _tokens[i];
                index++;
            }
        }

        return selectedTokens;
    }

    function testThisFunc2() public {
        bytes memory val = createBytes(address(weth), address(usdc), 5, 1);
        //console.logBytes(val);
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
