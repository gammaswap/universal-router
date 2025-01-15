// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import '../../contracts/routes/UniswapV2.sol';
import '../../contracts/routes/SushiswapV2.sol';
import '../../contracts/routes/DeltaSwap.sol';
import '../../contracts/routes/Aerodrome.sol';
import '../../contracts/routes/UniswapV3.sol';
import '../../contracts/routes/AerodromeCL.sol';
import "../../contracts/interfaces/IRouterExternalCallee.sol";
import '../../contracts/interfaces/IUniversalRouter.sol';
import './fixtures/TestBed.sol';
import './utils/Random.sol';

contract UniversalRouterTest is TestBed {

    using Path2 for bytes;
    using BytesLib2 for bytes;

    address owner;
    UniswapV2 uniV2Route;
    SushiswapV2 sushiV2Route;
    DeltaSwap dsRoute;
    Aerodrome aeroRoute;
    Aerodrome aeroStableRoute;
    UniswapV3 uniV3Route;
    AerodromeCL aeroCLRoute;
    Random random;
    address[] tokens;

    uint256 constant PROTOCOL_ROUTES_COUNT = 7;

    event ExternalCallSwap(
        address indexed sender,
        address indexed caller,
        uint256 indexed tokenId,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    event TrackPair(address indexed pair, address token0, address token1, uint24 fee, address factory, uint16 protocolId);
    event UnTrackPair(address indexed pair, address token0, address token1, uint24 fee, address factory, uint16 protocolId);

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

        bytes32 initCodeHash = 0xe18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303;

        uniV2Route = new UniswapV2(1, address(uniFactory), address(weth));
        sushiV2Route = new SushiswapV2(2, address(sushiFactory), address(weth), initCodeHash);
        dsRoute = new DeltaSwap(3, address(dsFactory), address(weth));
        aeroRoute = new Aerodrome(4, address(aeroFactory), false, address(weth));
        aeroStableRoute = new Aerodrome(5, address(aeroFactory), true, address(weth));
        uniV3Route = new UniswapV3(6, address(uniFactoryV3), address(weth));
        aeroCLRoute = new AerodromeCL(7, address(aeroCLFactory), address(weth));

        // set up routes
        router.addProtocolRoute(address(uniV2Route));
        router.addProtocolRoute(address(sushiV2Route));
        router.addProtocolRoute(address(dsRoute));
        router.addProtocolRoute(address(aeroRoute));
        router.addProtocolRoute(address(aeroStableRoute));
        router.addProtocolRoute(address(uniV3Route));
        router.addProtocolRoute(address(aeroCLRoute));
    }

    function testAddRemoveProtocol() public {
        vm.expectRevert('UniversalRouter: ZERO_ADDRESS');
        router.addProtocolRoute(address(0));

        UniswapV2 route0 = new UniswapV2(0, address(uniFactory), address(weth));
        vm.expectRevert('UniversalRouter: INVALID_PROTOCOL_ROUTE_ID');
        router.addProtocolRoute(address(route0));

        UniswapV2 route2 = new UniswapV2(20, address(uniFactory), address(weth));

        assertEq(router.protocolRoutes(20),address(0));

        assertEq(router.owner(), address(this));

        address userX = vm.addr(12345);
        vm.prank(userX);
        vm.expectRevert('Ownable: caller is not the owner');
        router.addProtocolRoute(address(route2));

        router.addProtocolRoute(address(route2));
        assertEq(router.protocolRoutes(20),address(route2));

        UniswapV2 route2a = new UniswapV2(20, address(uniFactory), address(weth));
        vm.expectRevert('UniversalRouter: PROTOCOL_ROUTE_ID_USED');
        router.addProtocolRoute(address(route2a));

        vm.prank(userX);
        vm.expectRevert('Ownable: caller is not the owner');
        router.removeProtocolRoute(0);

        vm.expectRevert('UniversalRouter: INVALID_PROTOCOL_ROUTE_ID');
        router.removeProtocolRoute(0);

        vm.expectRevert('UniversalRouter: PROTOCOL_ROUTE_ID_UNUSED');
        router.removeProtocolRoute(30);

        router.removeProtocolRoute(20);
        assertEq(router.protocolRoutes(20),address(0));
    }

    function testQuotes(uint8 tokenChoices, uint128 seed, uint256 amountIn) public {
        bytes memory path = createPath(tokenChoices, seed);
        uint256 minAmountOut;
        (amountIn, minAmountOut) = calcMinAmount(amountIn, path, true);
        uint256 amountOut = router.quote(amountIn, path);
        assertGt(amountOut,minAmountOut);
    }

    function testGetAmountsOut(uint8 tokenChoices, uint128 seed, uint256 amountIn) public {
        bytes memory path = createPath(tokenChoices, seed);
        IUniversalRouter.Route[] memory _routes = router.calcRoutes(path, address(this));
        uint256 minAmountOut;
        (amountIn, minAmountOut) = calcMinAmount(amountIn, path, true);
        (uint256[] memory amounts, IUniversalRouter.Route[] memory routes) = router.getAmountsOut(amountIn, path);
        assertEq(routes.length, _routes.length);
        assertEq(routes.length, amounts.length - 1);
        for(uint256 i = 0; i < _routes.length; i++) {
            assertEq(routes[i].from,_routes[i].from);
            assertEq(routes[i].to,_routes[i].to);
            assertEq(routes[i].pair,_routes[i].pair);
            assertEq(routes[i].protocolId,_routes[i].protocolId);
            if(routes[i].protocolId == 6 || routes[i].protocolId == 7) {
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

    function testGetAmountsIn(uint8 tokenChoices, uint128 seed, uint256 amountOut) public {
        bytes memory path = createPath(tokenChoices, seed);
        IUniversalRouter.Route[] memory _routes = router.calcRoutes(path, address(this));
        uint256 minAmountIn;
        (amountOut, minAmountIn) = calcMinAmount(amountOut, path, false);
        (uint256[] memory amounts, IUniversalRouter.Route[] memory routes) = router.getAmountsIn(amountOut, path);
        assertEq(routes.length, _routes.length);
        assertEq(routes.length, amounts.length - 1);
        for(uint256 i = 0; i < _routes.length; i++) {
            assertEq(routes[i].from,_routes[i].from);
            assertEq(routes[i].to,_routes[i].to);
            assertEq(routes[i].pair,_routes[i].pair);
            assertEq(routes[i].protocolId,_routes[i].protocolId);
            if(routes[i].protocolId == 6 || routes[i].protocolId == 7) {
                assertEq(routes[i].fee,_routes[i].fee);
            }
            assertEq(routes[i].origin,address(0));
            assertEq(routes[i].destination,address(0));
            assertEq(routes[i].hop,_routes[i].hop);
        }
        assertEq(amounts[amounts.length - 1], amountOut);
        for(uint256 i = 0; i < amounts.length; i++) {
            assertGt(amounts[i],0);
        }
        assertGt(amounts[0], minAmountIn);
    }

    function testSwapExactTokensForTokens1(uint8 tokenChoices, uint128 seed, uint256 amountIn) public {
        bytes memory path = createPath(tokenChoices, seed);
        IUniversalRouter.Route[] memory _routes = router.calcRoutes(path, address(this));
        (amountIn,) = calcMinAmount(amountIn, path, true);
        (uint256[] memory amounts, IUniversalRouter.Route[] memory routes) = router.getAmountsOut(amountIn, path);

        uint256 minAmountOut = amounts[amounts.length - 1];
        address _to = vm.addr(0x123);

        uint256 balanceTo0 = IERC20(_routes[_routes.length - 1].to).balanceOf(_to);
        uint256 balanceFrom0 = IERC20(_routes[0].from).balanceOf(owner);

        vm.startPrank(owner);
        IERC20(_routes[0].from).approve(address(router), type(uint256).max);

        vm.expectRevert('UniversalRouter: EXPIRED');
        router.swapExactTokensForTokens(amountIn, minAmountOut, path, _to, block.timestamp - 1);

        vm.expectRevert('UniversalRouter: ZERO_AMOUNT_IN');
        router.swapExactTokensForTokens(0, minAmountOut, path, _to, block.timestamp);

        vm.expectRevert('UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        router.swapExactTokensForTokens(amountIn, minAmountOut + 1, path, _to, block.timestamp);

        router.swapExactTokensForTokens(amountIn, minAmountOut, path, _to, block.timestamp);

        uint256 balanceTo1 = IERC20(_routes[_routes.length - 1].to).balanceOf(_to);
        uint256 balanceFrom1 = IERC20(_routes[0].from).balanceOf(owner);

        assertEq(amountIn, balanceFrom0 - balanceFrom1);
        assertEq(minAmountOut, balanceTo1 - balanceTo0);
        vm.stopPrank();
    }

    function testSwapExactTokensForTokens2(uint8 tokenChoices, uint128 seed, uint256 amountOut) public {
        bytes memory path = createPath(tokenChoices, seed);
        IUniversalRouter.Route[] memory _routes = router.calcRoutes(path, address(this));
        (amountOut,) = calcMinAmount(amountOut, path, false);
        (uint256[] memory amounts, IUniversalRouter.Route[] memory routes) = router.getAmountsIn(amountOut, path);

        uint256 amountIn = amounts[0];
        address _to = vm.addr(0x123);

        uint256 balanceTo0 = IERC20(_routes[_routes.length - 1].to).balanceOf(_to);
        uint256 balanceFrom0 = IERC20(_routes[0].from).balanceOf(owner);

        vm.startPrank(owner);
        IERC20(_routes[0].from).approve(address(router), type(uint256).max);

        vm.expectRevert('UniversalRouter: EXPIRED');
        router.swapExactTokensForTokens(amountIn, amountOut, path, _to, block.timestamp - 1);

        vm.expectRevert('UniversalRouter: ZERO_AMOUNT_IN');
        router.swapExactTokensForTokens(0, amountOut, path, _to, block.timestamp);

        vm.expectRevert('UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        router.swapExactTokensForTokens(amountIn, amountOut * 101 / 100, path, _to, block.timestamp);

        router.swapExactTokensForTokens(amountIn, amountOut, path, _to, block.timestamp);

        uint256 balanceTo1 = IERC20(_routes[_routes.length - 1].to).balanceOf(_to);
        uint256 balanceFrom1 = IERC20(_routes[0].from).balanceOf(owner);

        assertEq(amountIn, balanceFrom0 - balanceFrom1);
        assertApproxEqRel(amountOut, balanceTo1 - balanceTo0, 1e16);
        vm.stopPrank();
    }

    function testSwapExactETHForTokens(uint8 tokenChoices, uint128 seed, uint256 amountIn) public {
        bytes memory path = createPath(tokenChoices, seed);
        IUniversalRouter.Route[] memory _routes = router.calcRoutes(path, address(this));

        if(_routes[0].from != address(weth)) {
            vm.expectRevert('UniversalRouter: AMOUNT_IN_NOT_ETH');
            router.swapExactETHForTokens(0, path, owner, block.timestamp);

            if(_routes[0].to == address(weth)) {
                if(path.hasMultiplePools()) {
                    path = path.skipToken();
                } else {
                    path = abi.encodePacked(_routes[0].to, uint16(1), uint24(0), _routes[0].from);
                }
            } else {
                path = abi.encodePacked(address(weth), uint16(1), uint24(0), path);
            }
        }

        _routes = router.calcRoutes(path, address(this));
        (amountIn,) = calcMinAmount(amountIn, path, true);
        (uint256[] memory amounts, IUniversalRouter.Route[] memory routes) = router.getAmountsOut(amountIn, path);

        uint256 minAmountOut = amounts[amounts.length - 1];
        address _to = vm.addr(0x123);

        vm.expectRevert('UniversalRouter: EXPIRED');
        router.swapExactETHForTokens(minAmountOut, path, _to, block.timestamp - 1);

        vm.expectRevert('UniversalRouter: ZERO_AMOUNT_IN');
        router.swapExactETHForTokens(minAmountOut, path, _to, block.timestamp);

        vm.expectRevert('UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        router.swapExactETHForTokens{value: amountIn}(minAmountOut + 1, path, _to, block.timestamp);

        uint256 balanceTo0 = IERC20(_routes[_routes.length - 1].to).balanceOf(_to);
        uint256 balanceFrom0 = address(this).balance;

        router.swapExactETHForTokens{value: amountIn}(minAmountOut, path, _to, block.timestamp);

        uint256 balanceTo1 = IERC20(_routes[_routes.length - 1].to).balanceOf(_to);
        uint256 balanceFrom1 = address(this).balance;

        assertEq(amountIn, balanceFrom0 - balanceFrom1);
        assertEq(minAmountOut, balanceTo1 - balanceTo0);
    }

    function testSwapExactTokensForETH(uint8 tokenChoices, uint128 seed, uint256 amountIn) public {
        bytes memory path = createPath(tokenChoices, seed);
        IUniversalRouter.Route[] memory _routes = router.calcRoutes(path, address(this));

        if(_routes[_routes.length - 1].to != address(weth)) {
            vm.expectRevert('UniversalRouter: AMOUNT_OUT_NOT_ETH');
            router.swapExactTokensForETH(0, 0, path, owner, block.timestamp);

            if(_routes[_routes.length - 1].from == address(weth)) {
                if(path.hasMultiplePools()) {
                    path = path.hopToken();
                } else {
                    path = abi.encodePacked(_routes[_routes.length - 1].to, uint16(1), uint24(0), _routes[_routes.length - 1].from);
                }
            } else {
                path = abi.encodePacked(path, uint16(1), uint24(0), address(weth));
            }
        }

        _routes = router.calcRoutes(path, address(this));
        (amountIn,) = calcMinAmount(amountIn, path, true);
        (uint256[] memory amounts, IUniversalRouter.Route[] memory routes) = router.getAmountsOut(amountIn, path);

        uint256 minAmountOut = amounts[amounts.length - 1];
        address _to = vm.addr(0x123);

        uint256 balanceTo0 = address(_to).balance;
        uint256 balanceFrom0 = IERC20(_routes[0].from).balanceOf(owner);

        weth.deposit{value: 50e18}();

        vm.startPrank(owner);
        IERC20(_routes[0].from).approve(address(router), type(uint256).max);

        vm.expectRevert("UniversalRouter: EXPIRED");
        router.swapExactTokensForETH(amountIn, minAmountOut, path, _to, block.timestamp - 1);

        vm.expectRevert("UniversalRouter: ZERO_AMOUNT_IN");
        router.swapExactTokensForETH(0, minAmountOut, path, _to, block.timestamp);

        vm.expectRevert("UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        router.swapExactTokensForETH(amountIn, minAmountOut + 1, path, _to, block.timestamp);

        router.swapExactTokensForETH(amountIn, minAmountOut, path, _to, block.timestamp);

        uint256 balanceTo1 =address(_to).balance;
        uint256 balanceFrom1 = IERC20(_routes[0].from).balanceOf(owner);

        assertEq(amountIn, balanceFrom0 - balanceFrom1);
        assertEq(minAmountOut, balanceTo1 - balanceTo0);
        vm.stopPrank();
    }

    function calcMinAmount(uint256 amount, bytes memory path, bool isAmountIn) internal view returns(uint256, uint256) {
        IUniversalRouter.Route[] memory routes = router.calcRoutes(path, address(router));
        uint256 minAmount;
        address _fromToken = isAmountIn ? routes[0].from : routes[routes.length - 1].to;
        address _toToken = isAmountIn ? routes[routes.length - 1].to : routes[0].from;
        if(_fromToken == address(weth)) {
            amount = bound(amount, 1e18, 10e18);
            if(_toToken == address(wbtc)) {
                minAmount = 4400384;
            } else if(_toToken == address(dai)) {
                minAmount = 2800e18;
            } else {
                minAmount = 2800e6;
            }
        } else if(_fromToken == address(wbtc)) {
            amount = bound(amount, 1e6, 1e8);
            if(_toToken == address(weth)) {
                minAmount = 2e17;
            } else if(_toToken == address(dai)) {
                minAmount = 620e18;
            } else {
                minAmount = 620e6;
            }
        } else if(_fromToken == address(dai)) {
            amount = bound(amount, 1e18, 1000e18);
            if(_toToken == address(weth)) {
                minAmount = 313333333333333;
            } else if(_toToken == address(wbtc)) {
                minAmount = 1450;
            } else {
                minAmount = 9e5;
            }
        } else {
            amount = bound(amount, 1e6, 1000e6);
            if(_toToken == address(weth)) {
                minAmount = 313333333333333;
            } else if(_toToken == address(wbtc)) {
                minAmount = 1450;
            } else if(_toToken == address(dai)) {
                minAmount = 9e17;
            } else {
                minAmount = 9e5;
            }
        }
        return (amount, minAmount);
    }

    function testCalcRoutes(uint8 tokenChoices, uint128 seed) public {
        bytes memory path = createPath(tokenChoices, seed);
        address to = vm.addr(0x123);
        IUniversalRouter.Route[] memory routes = router.calcRoutes(path, to);
        for(uint256 i = 0; i < routes.length; i++) {
            address pair = getPair(routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee);
            assertTrue(pair != address(0));
            assertTrue(validateTokens(routes[i].from, routes[i].to, pair));
            assertEq(routes[i].hop, router.protocolRoutes(routes[i].protocolId));
            assertEq(routes[i].pair, pair);
            if(routes[i].protocolId == 6 || routes[i].protocolId == 7) {
                assertEq(routes[i].origin, router.protocolRoutes(routes[i].protocolId));
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
        } else if(protocolId == 7) {
            return aeroCLFactory.getPool(from, to, int24(fee));
        }
        return address(0);
    }

    function getFactory(uint16 protocolId) internal view returns(address) {
        if(protocolId == 1) {
            return address(uniFactory);
        } else if(protocolId == 2) {
            return address(sushiFactory);
        } else if(protocolId == 3) {
            return address(dsFactory);
        } else if(protocolId == 4) {
            return address(aeroFactory);
        } else if(protocolId == 5) {
            return address(aeroFactory);
        } else if(protocolId == 6) {
            return address(uniFactoryV3);
        } else if(protocolId == 7) {
            return address(aeroCLFactory);
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
            uint24 fee = protocolId == 6 ? poolFee1 : protocolId == 7 ? uint24(aeroCLTickSpacing): 0;
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

    function testCalcRoutesErrors() public {
        bytes memory path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b';

        vm.expectRevert('UniversalRouter: PROTOCOL_ROUTE_NOT_SET');
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C5847';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470bff';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000b';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff00';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8F62849F9A0B5Bf2913b396098F7c7019b51A820a';
        vm.expectRevert('UniversalRouter: PROTOCOL_ROUTE_NOT_SET');
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A90001000bb82e234DAe75C793f67A35089C9d99245E1C58470b0001000bb8F62849F9A0B5Bf2913b396098F7c7019b51A820a';
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A90001000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8F62849F9A0B5Bf2913b396098F7c7019b51A82';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.calcRoutes(path, address(this));
    }

    function testGetAmountsOutErrors() public {
        bytes memory path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b';

        vm.expectRevert('UniversalRouter: PROTOCOL_ROUTE_NOT_SET');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C5847';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470bff';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000b';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff00';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8F62849F9A0B5Bf2913b396098F7c7019b51A820a';
        vm.expectRevert('UniversalRouter: PROTOCOL_ROUTE_NOT_SET');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A90001000bb82e234DAe75C793f67A35089C9d99245E1C58470b0001000bb8F62849F9A0B5Bf2913b396098F7c7019b51A820a';
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A90001000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8F62849F9A0B5Bf2913b396098F7c7019b51A82';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.getAmountsOut(1e18, path);
    }

    function testGetAmountsInErrors() public {
        bytes memory path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b';

        vm.expectRevert('UniversalRouter: PROTOCOL_ROUTE_NOT_SET');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C5847';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470bff';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000b';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff00';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8F62849F9A0B5Bf2913b396098F7c7019b51A820a';
        vm.expectRevert('UniversalRouter: PROTOCOL_ROUTE_NOT_SET');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A90001000bb82e234DAe75C793f67A35089C9d99245E1C58470b0001000bb8F62849F9A0B5Bf2913b396098F7c7019b51A820a';
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A90001000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8F62849F9A0B5Bf2913b396098F7c7019b51A82';
        vm.expectRevert('UniversalRouter: INVALID_PATH');
        router.getAmountsIn(1e6, path);
    }

    function testRoutePath() public {
        bytes memory val = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab1';
        address res = router._getTokenOut(val);
        assertEq(res,0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        val = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e5831';
        res = router._getTokenOut(val);
        assertEq(res,0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        val = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e5831000100010076991314cEE341ebE37e6E2712cb04F5d56dE355';
        res = router._getTokenOut(val);
        assertEq(res,0x76991314cEE341ebE37e6E2712cb04F5d56dE355);
        val = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e5831000100010076991314cEE341ebE37e6E2712cb04F5d56dE3550001000100F6D9C101ceeA72655A13a8Cf1C88c1949Ed399bc';
        res = router._getTokenOut(val);
        assertEq(res,0xF6D9C101ceeA72655A13a8Cf1C88c1949Ed399bc);
    }

    function testCalcPathFee() public {
        bytes memory pathUsdcToWeth = abi.encodePacked(address(usdc), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(weth));
        uint256 pathFee = router.calcPathFee(pathUsdcToWeth);
        assertEq(pathFee, 5991);

        bytes memory pathWethToUsdc = abi.encodePacked(address(weth), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(usdc));
        pathFee = router.calcPathFee(pathWethToUsdc);
        assertEq(pathFee, 5991);

        bytes memory pathWethToDai = abi.encodePacked(address(weth), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(usdc), uint16(6), poolFee1, address(dai));
        pathFee = router.calcPathFee(pathWethToDai);
        assertEq(pathFee, 15932);
     }

    function testPathFees(uint8 tokenChoices, uint128 seed) public {
        bytes memory path = createPath(tokenChoices, seed);
        IUniversalRouter.Route[] memory _routes = router.calcRoutes(path, address(this));
        uint256 minAmountOut;
        uint256 amountIn = getMinAmountIn(_routes[0].from);
        uint256 amountOut = router.quote(amountIn, path);
        uint256 pathFee = router.calcPathFee(path);
        uint256 amountOutPostFees = amountOut - amountOut * pathFee / 1e6;

        vm.startPrank(owner);

        uint256 balanceTo0 = IERC20(_routes[_routes.length - 1].to).balanceOf(owner);
        uint256 balanceFrom0 = IERC20(_routes[0].from).balanceOf(owner);

        IERC20(_routes[0].from).approve(address(router), type(uint256).max);

        router.swapExactTokensForTokens(amountIn, 0, path, owner, block.timestamp);

        uint256 balanceTo1 = IERC20(_routes[_routes.length - 1].to).balanceOf(owner);
        uint256 balanceFrom1 = IERC20(_routes[0].from).balanceOf(owner);

        uint256 soldAmount = balanceFrom0 - balanceFrom1;
        uint256 boughtAmount = balanceTo1 - balanceTo0;
        assertApproxEqRel(amountOutPostFees, boughtAmount, 1e16);

        vm.stopPrank();
    }

    function getMinAmountIn(address token) internal view returns(uint256) {
        if(token == address(weth)) {
            return 1e14;
        } else if(token == address(wbtc)) {
            return 1e4;
        } else if(token == address(dai)) {
            return 1e18;
        }
        return 1e6;
    }

    function testExternalCallSwap(uint256 deltaUSDC, uint256 deltaWETH, bool isBuyWeth) public {
        deltaUSDC = bound(deltaUSDC, 10e6, 1_000e6);
        deltaWETH = bound(deltaWETH, 1e16, 10e18);

        bytes memory pathUsdcToWeth = abi.encodePacked(address(usdc), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(weth));
        bytes memory pathWethToUsdc = abi.encodePacked(address(weth), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(usdc));

        UniversalRouter.ExternalCallData memory data;

        if (isBuyWeth) {
            data = IRouterExternalCallee.ExternalCallData({
                amountIn: deltaUSDC,
                minAmountOut: 0,
                deadline: type(uint256).max,
                tokenId: 100,
                path: pathUsdcToWeth
            });
        } else {
            data = IRouterExternalCallee.ExternalCallData({
                amountIn: deltaWETH,
                minAmountOut: 0,
                deadline: type(uint256).max,
                tokenId: 100,
                path: pathWethToUsdc
            });
        }

        uint128[] memory amounts = new uint128[](2);
        amounts[0] = uint128(deltaUSDC);
        amounts[1] = uint128(deltaWETH);

        usdc.mintExact(address(router), deltaUSDC);
        weth.mintExact(address(router), deltaWETH);

        uint256 balanceUSDC = usdc.balanceOf(address(this));
        uint256 balanceWETH = weth.balanceOf(address(this));
        assertEq(usdc.balanceOf(address(this)), 0);
        assertEq(weth.balanceOf(address(this)), 0);
        assertEq(usdc.balanceOf(address(router)), deltaUSDC);
        assertEq(weth.balanceOf(address(router)), deltaWETH);

        // Avoid stack-too-deep
        {
            (uint256[] memory amountsOut,) = router.getAmountsOut(data.amountIn, data.path);

            vm.expectEmit();
            emit ExternalCallSwap(vm.addr(1), address(this), data.tokenId, isBuyWeth ? address(usdc) : address(weth), isBuyWeth ? address(weth) : address(usdc), data.amountIn, amountsOut[amountsOut.length - 1]);
            router.externalCall(vm.addr(1), amounts, 0, abi.encode(data));
        }

        if(isBuyWeth) {
            assertEq(usdc.balanceOf(address(this)), balanceUSDC);
            assertGt(weth.balanceOf(address(this)), balanceWETH);
        } else {
            assertGt(usdc.balanceOf(address(this)), balanceUSDC);
            assertEq(weth.balanceOf(address(this)), balanceWETH);
        }
        assertEq(usdc.balanceOf(address(router)), 0);
        assertEq(weth.balanceOf(address(router)), 0);
    }

    function testGetPairInfo() public {
        for(uint16 protocolId = 1; protocolId < 8; protocolId++) {
            uint24 _poolFee = protocolId == 6 ? poolFee1 : protocolId == 7 ? uint24(aeroCLTickSpacing) : 0;
            (address token0, address token1) = protocolId == 5 ? (address(usdc), address(usdt)) : (address(weth), address(usdc));
            (address _pair0,,,address _factory0) = router.getPairInfo(token0, token1, _poolFee, protocolId);
            (address _pair1,,,address _factory1) = router.getPairInfo(token1, token0, _poolFee, protocolId);
            assertEq(_pair0,getPair(token0, token1, protocolId, _poolFee));
            assertEq(_pair1,getPair(token1, token0, protocolId, _poolFee));
            assertEq(_factory0, getFactory(protocolId));
            assertEq(_factory1, getFactory(protocolId));
        }
    }

    function testTrackPair0() public {
        assertEq(router.owner(), address(this));
        for(uint16 protocolId = 1; protocolId < 8; protocolId++) {
            uint24 _poolFee = protocolId == 6 ? poolFee1 : protocolId == 7 ? uint24(aeroCLTickSpacing) : 0;
            (address token0, address token1) = protocolId == 5 ? (address(usdc), address(usdt)) : (address(weth), address(usdc));
            (address pair, address _token0, address _token1, address _factory) = router.getPairInfo(token0, token1, _poolFee, protocolId);

            assertEq(pair, getPair(token0, token1, protocolId, _poolFee));
            assertEq(_factory, getFactory(protocolId));
            assertEq(router.trackedPairs(pair), 0);

            vm.prank(vm.addr(1));
            vm.expectRevert("Ownable: caller is not the owner");
            router.trackPair(token0, token1, _poolFee, protocolId);

            vm.expectEmit();
            emit TrackPair(pair, _token0, _token1, _poolFee, _factory, protocolId);
            router.trackPair(token0, token1, _poolFee, protocolId);

            assertEq(router.trackedPairs(pair), block.timestamp);

            vm.expectEmit();
            emit TrackPair(pair, _token0, _token1, _poolFee, _factory, protocolId);
            router.trackPair(token0, token1, _poolFee, protocolId);

            assertEq(router.trackedPairs(pair), block.timestamp);
        }

        for(uint16 protocolId = 1; protocolId < 8; protocolId++) {
            uint24 _poolFee = protocolId == 6 ? poolFee1 : protocolId == 7 ? uint24(aeroCLTickSpacing) : 0;
            (address token0, address token1) = protocolId == 5 ? (address(usdc), address(usdt)) : (address(weth), address(usdc));
            (address pair, address _token0, address _token1, address _factory) = router.getPairInfo(token0, token1, _poolFee, protocolId);

            assertEq(pair, getPair(token0, token1, protocolId, _poolFee));
            assertEq(_factory, getFactory(protocolId));
            assertGe(router.trackedPairs(pair), block.timestamp);

            vm.prank(vm.addr(1));
            vm.expectRevert("Ownable: caller is not the owner");
            router.unTrackPair(token0, token1, _poolFee, protocolId);

            vm.expectEmit();
            emit UnTrackPair(pair, _token0, _token1, _poolFee, _factory, protocolId);
            router.unTrackPair(token0, token1, _poolFee, protocolId);

            assertEq(router.trackedPairs(pair), 0);

            vm.expectEmit();
            emit UnTrackPair(pair, _token0, _token1, _poolFee, _factory, protocolId);
            router.unTrackPair(token0, token1, _poolFee, protocolId);

            assertEq(router.trackedPairs(pair), 0);
        }
    }

    function testTrackPair1() public {
        assertEq(router.owner(), address(this));
        for(uint16 protocolId = 1; protocolId < 8; protocolId++) {
            uint24 _poolFee = protocolId == 6 ? poolFee1 : protocolId == 7 ? uint24(aeroCLTickSpacing) : 0;
            (address token0, address token1) = protocolId == 5 ? (address(usdt), address(usdc)) : (address(usdc), address(weth));
            (address pair, address _token0, address _token1, address _factory) = router.getPairInfo(token0, token1, _poolFee, protocolId);

            assertEq(pair, getPair(token0, token1, protocolId, _poolFee));
            assertEq(_factory, getFactory(protocolId));
            assertEq(router.trackedPairs(pair), 0);

            vm.prank(vm.addr(1));
            vm.expectRevert("Ownable: caller is not the owner");
            router.trackPair(token0, token1, _poolFee, protocolId);

            vm.expectEmit();
            emit TrackPair(pair, _token0, _token1, _poolFee, _factory, protocolId);
            router.trackPair(token0, token1, _poolFee, protocolId);

            assertEq(router.trackedPairs(pair), block.timestamp);

            vm.expectEmit();
            emit TrackPair(pair, _token0, _token1, _poolFee, _factory, protocolId);
            router.trackPair(token0, token1, _poolFee, protocolId);

            assertEq(router.trackedPairs(pair), block.timestamp);
        }

        for(uint16 protocolId = 1; protocolId < 8; protocolId++) {
            uint24 _poolFee = protocolId == 6 ? poolFee1 : protocolId == 7 ? uint24(aeroCLTickSpacing) : 0;
            (address token0, address token1) = protocolId == 5 ? (address(usdt), address(usdc)) : (address(usdc), address(weth));
            (address pair, address _token0, address _token1, address _factory) = router.getPairInfo(token0, token1, _poolFee, protocolId);

            assertEq(pair, getPair(token0, token1, protocolId, _poolFee));
            assertEq(_factory, getFactory(protocolId));
            assertGe(router.trackedPairs(pair), block.timestamp);

            vm.prank(vm.addr(1));
            vm.expectRevert("Ownable: caller is not the owner");
            router.unTrackPair(token0, token1, _poolFee, protocolId);

            vm.expectEmit();
            emit UnTrackPair(pair, _token0, _token1, _poolFee, _factory, protocolId);
            router.unTrackPair(token0, token1, _poolFee, protocolId);

            assertEq(router.trackedPairs(pair), 0);

            vm.expectEmit();
            emit UnTrackPair(pair, _token0, _token1, _poolFee, _factory, protocolId);
            router.unTrackPair(token0, token1, _poolFee, protocolId);

            assertEq(router.trackedPairs(pair), 0);
        }
    }
}
