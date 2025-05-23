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
        vm.expectRevert(bytes4(keccak256('InvalidProtocolRouteID()')));
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
        vm.expectRevert(bytes4(keccak256('UsedProtocolRouteID()')));
        router.addProtocolRoute(address(route2a));

        vm.prank(userX);
        vm.expectRevert('Ownable: caller is not the owner');
        router.removeProtocolRoute(0);

        vm.expectRevert(bytes4(keccak256('InvalidProtocolRouteID()')));
        router.removeProtocolRoute(0);

        vm.expectRevert(bytes4(keccak256('UnusedProtocolRouteID()')));
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

    function testQuotesSplit(uint8 tokenChoices, uint64 seed, uint256 amountIn) public {
        bytes[] memory paths;
        uint256[] memory weights;
        uint256 minAmountOut;
        (paths, weights, amountIn, minAmountOut) = getPathsAndWeights(tokenChoices, seed, amountIn, false, true);

        uint256 amountOut = router.quoteSplit(amountIn, paths, weights);
        uint256 expAmountOut = 0;

        uint256[] memory amountsIn = router.splitAmount(amountIn, weights);
        for(uint256 i = 0; i < paths.length; i++) {
            expAmountOut += router.quote(amountsIn[i], paths[i]);
        }
        assertEq(amountOut,expAmountOut);

        uint256 sumWeights = 0;
        for(uint256 i = 0; i < weights.length; i++) {
            sumWeights += weights[i];
        }

        expAmountOut = 0;
        for(uint256 i = 0; i < paths.length; i++) {
            uint256 amt = amountIn * weights[i] / sumWeights;
            expAmountOut += router.quote(amt, paths[i]);
        }
        assertApproxEqRel(amountOut,expAmountOut,1e14);

        assertGt(amountOut,minAmountOut);
    }

    function testQuotesSplit0(uint8 tokenChoices, uint64 seed, uint256 amountIn) public {
        bytes[] memory paths;
        uint256[] memory weights;
        uint256 minAmountOut;
        (paths, weights, amountIn, minAmountOut) = getPathsAndWeights(tokenChoices, seed, amountIn, false, true);

        bytes memory path = Path2.fromPathsAndWeightsArray(paths,weights);
        uint256 amountOut = router.quote(amountIn, path);
        uint256 expAmountOut = 0;

        uint256[] memory amountsIn = router.splitAmount(amountIn, weights);
        for(uint256 i = 0; i < paths.length; i++) {
            expAmountOut += router.quote(amountsIn[i], paths[i]);
        }
        assertEq(amountOut,expAmountOut);

        uint256 sumWeights = 0;
        for(uint256 i = 0; i < weights.length; i++) {
            sumWeights += weights[i];
        }

        expAmountOut = 0;
        for(uint256 i = 0; i < paths.length; i++) {
            uint256 amt = amountIn * weights[i] / sumWeights;
            expAmountOut += router.quote(amt, paths[i]);
        }
        assertApproxEqRel(amountOut,expAmountOut,1e14);

        assertGt(amountOut,minAmountOut);
    }

    function testSplitAmount(uint256 amount, uint8 numOfPaths) public {
        amount = boundVar(amount, 1e2, type(uint128).max);
        numOfPaths = numOfPaths == 0 ? 1 : numOfPaths;

        uint256 totalSum = 0;
        uint256[] memory weights = random.generateWeights(numOfPaths);
        for(uint256 i = 0; i < weights.length; i++) {
            totalSum += weights[i];
        }
        assertEq(totalSum, 1e18);

        uint256 totalAmounts = 0;
        uint256[] memory amounts = router.splitAmount(amount, weights);
        for(uint256 i = 0; i < amounts.length; i++) {
            totalAmounts += amounts[i];
        }
        assertEq(totalAmounts, amount);

        assertEq(amounts.length, weights.length);
    }

    function sumAmounts(uint256[][] memory amounts, bool isAmountIn) internal view returns(uint256 totalAmount) {
        for(uint256 i = 0; i < amounts.length; i++) {
            if(isAmountIn) {
                totalAmount += amounts[i][0];
            } else {
                totalAmount += amounts[i][amounts[i].length - 1];
            }
        }
    }

    function getPathsAndWeights(uint8 tokenChoices, uint64 seed, uint256 amountIn, bool isUniquePaths, bool isAmountIn) internal returns(bytes[] memory, uint256[] memory, uint256, uint256) {
        bytes[] memory paths;
        if(isUniquePaths) {
            paths = createPaths2(createPath(tokenChoices, seed), seed);
        } else {
            paths = createPaths(createPath(tokenChoices, seed), seed, 2);
        }
        uint256 minAmountOut;
        {
            (amountIn, minAmountOut) = calcMinAmount(amountIn, paths[0], isAmountIn);
            minAmountOut = minAmountOut * 99/100;
            address tokenIn = paths[0].getTokenIn();
            address tokenOut = paths[0].getTokenOut();
            for(uint256 i = 0; i < paths.length; i++) {
                assertEq(tokenIn,paths[i].getTokenIn());
                assertEq(tokenOut,paths[i].getTokenOut());
            }
        }
        uint256[] memory weights = random.generateWeights(paths.length);
        uint256 sumOfWeights = 0;
        for(uint256 i = 0; i < weights.length; i++) {
            sumOfWeights += weights[i];
        }
        assertEq(sumOfWeights,1e18);
        assertEq(paths.length,weights.length);
        return(paths, weights, amountIn, minAmountOut);
    }

    function testGetAmountsOutSplit(uint8 tokenChoices, uint64 seed, uint256 amountIn) public {
        bytes[] memory paths;
        uint256[] memory weights;
        uint256 minAmountOut;
        (paths, weights, amountIn, minAmountOut) = getPathsAndWeights(tokenChoices, seed, amountIn, false, true);

        (uint256 amountOut, uint256[][] memory amountsSplit, IUniversalRouter.Route[][] memory routesSplit) =
            router.getAmountsOutSplit(amountIn, paths, weights);
        for(uint256 i = 0; i < paths.length; i++) {
            IUniversalRouter.Route[] memory _routes = router.calcRoutes(paths[i], address(this));
            assertEq(_routes.length,routesSplit[i].length);
            for(uint256 j = 0; j < _routes.length;j++) {
                assertEq(_routes[j].from,routesSplit[i][j].from);
                assertEq(_routes[j].to,routesSplit[i][j].to);
                assertEq(_routes[j].pair,routesSplit[i][j].pair);
                assertEq(_routes[j].protocolId,routesSplit[i][j].protocolId);
                if(_routes[j].protocolId == 6 || _routes[j].protocolId == 7) {
                    assertEq(_routes[j].fee,routesSplit[i][j].fee);
                }
                assertEq(address(0),routesSplit[i][j].origin);
                assertEq(address(0),routesSplit[i][j].destination);
                assertEq(_routes[j].hop,routesSplit[i][j].hop);
            }
        }

        assertEq(sumAmounts(amountsSplit,true), amountIn);
        for(uint256 i = 0; i < amountsSplit.length; i++) {
            for(uint256 j = 0; j < amountsSplit[i].length; j++) {
                assertGt(amountsSplit[i][j],0);
            }
        }
        assertEq(sumAmounts(amountsSplit,false), amountOut);
        assertGt(sumAmounts(amountsSplit,false), minAmountOut);
    }

    function testGetAmountsOutSplitNoSwap(uint8 tokenChoices, uint64 seed, uint256 amountIn) public {
        bytes[] memory paths;
        uint256[] memory weights;
        uint256 minAmountOut;
        (paths, weights, amountIn, minAmountOut) = getPathsAndWeights(tokenChoices, seed, amountIn, false, true);

        (uint256 amountOut, uint256[][] memory amountsSplit, IUniversalRouter.Route[][] memory routesSplit) =
            router.getAmountsOutSplitNoSwap(amountIn, paths, weights);

        for(uint256 i = 0; i < paths.length; i++) {
            IUniversalRouter.Route[] memory _routes = router.calcRoutes(paths[i], address(this));
            assertEq(_routes.length,routesSplit[i].length);
            for(uint256 j = 0; j < _routes.length;j++) {
                assertEq(_routes[j].from,routesSplit[i][j].from);
                assertEq(_routes[j].to,routesSplit[i][j].to);
                assertEq(_routes[j].pair,routesSplit[i][j].pair);
                assertEq(_routes[j].protocolId,routesSplit[i][j].protocolId);
                if(_routes[j].protocolId == 6 || _routes[j].protocolId == 7) {
                    assertEq(_routes[j].fee,routesSplit[i][j].fee);
                }
                assertEq(address(0),routesSplit[i][j].origin);
                assertEq(address(0),routesSplit[i][j].destination);
                assertEq(_routes[j].hop,routesSplit[i][j].hop);
            }
        }

        assertEq(amountsSplit.length, paths.length);
        assertEq(sumAmounts(amountsSplit,true), amountIn);
        for(uint256 i = 0; i < amountsSplit.length; i++) {
            for(uint256 j = 0; j < amountsSplit[i].length; j++) {
                if(amountIn >= 1e16) {
                    assertGt(amountsSplit[i][j],0);
                } else {
                    assertGe(amountsSplit[i][j],0);
                }
            }
        }
        if(amountIn >= 1e16) {
            assertGt(sumAmounts(amountsSplit,false), minAmountOut);
        } else {
            assertGe(sumAmounts(amountsSplit,false), minAmountOut);
        }
    }

    function testGetAmountsInSplit(uint8 tokenChoices, uint64 seed, uint256 amountOut) public {
        bytes[] memory paths;
        uint256[] memory weights;
        uint256 minAmountIn;
        (paths, weights, amountOut, minAmountIn) = getPathsAndWeights(tokenChoices, seed, amountOut, false, false);

        (uint256 amountIn, uint256[] memory inWeights, uint256[][] memory amountsSplit, IUniversalRouter.Route[][] memory routesSplit) =
            router.getAmountsInSplit(amountOut, paths, weights);

        for(uint256 i = 0; i < paths.length; i++) {
            IUniversalRouter.Route[] memory _routes = router.calcRoutes(paths[i], address(this));
            assertEq(_routes.length,routesSplit[i].length);
            for(uint256 j = 0; j < _routes.length; j++) {
                assertEq(_routes[j].from,routesSplit[i][j].from);
                assertEq(_routes[j].to,routesSplit[i][j].to);
                assertEq(_routes[j].pair,routesSplit[i][j].pair);
                assertEq(_routes[j].protocolId,routesSplit[i][j].protocolId);
                if(_routes[j].protocolId == 6 || _routes[j].protocolId == 7) {
                    assertEq(_routes[j].fee,routesSplit[i][j].fee);
                }
                assertEq(address(0),routesSplit[i][j].origin);
                assertEq(address(0),routesSplit[i][j].destination);
                assertEq(_routes[j].hop,routesSplit[i][j].hop);
            }
        }

        assertEq(sumAmounts(amountsSplit,true), amountIn);
        for(uint256 i = 0; i < amountsSplit.length; i++) {
            for(uint256 j = 0; j < amountsSplit[i].length; j++) {
                assertGt(amountsSplit[i][j],0);
            }
        }
        assertEq(sumAmounts(amountsSplit,false), amountOut);
        assertGt(sumAmounts(amountsSplit,true), minAmountIn);
    }

    function testGetAmountsOutNoSwap(uint8 tokenChoices, uint128 seed, uint256 amountIn) public {
        bytes memory path = createPath(tokenChoices, seed);
        IUniversalRouter.Route[] memory _routes = router.calcRoutes(path, address(this));
        uint256 minAmountOut;
        (amountIn, minAmountOut) = calcMinAmountNoSwap(amountIn, path, true);
        (uint256[] memory amounts, IUniversalRouter.Route[] memory routes) = router.getAmountsOutNoSwap(amountIn, path);
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
            if(amounts[0] >= 1e16) {
                assertGt(amounts[i],0);
            } else {
                assertGe(amounts[i],0);
            }
        }
        if(amounts[0] >= 1e16) {
            assertGt(amounts[amounts.length - 1], minAmountOut);
        } else {
            assertGe(amounts[amounts.length - 1], minAmountOut);
        }
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

    function testSwapExactTokensForTokensSplit1(uint8 tokenChoices, uint64 seed, uint256 amountIn) public {
        bytes[] memory paths;
        uint256[] memory weights;
        uint256 minAmountOut;
        (paths, weights, amountIn, minAmountOut) = getPathsAndWeights(tokenChoices, seed, amountIn, true, true);

        (uint256 amountOut, uint256[][] memory amountsSplit, IUniversalRouter.Route[][] memory routesSplit) = router.getAmountsOutSplit(amountIn, paths, weights);

        assertEq(amountOut,sumAmounts(amountsSplit,false));

        minAmountOut = amountOut;
        address _to = vm.addr(0x123);

        uint256 balanceTo0 = IERC20(routesSplit[0][routesSplit[0].length - 1].to).balanceOf(_to);
        uint256 balanceFrom0 = IERC20(routesSplit[0][0].from).balanceOf(owner);

        vm.startPrank(owner);
        IERC20(routesSplit[0][0].from).approve(address(router), type(uint256).max);

        vm.expectRevert(bytes4(keccak256("Expired()")));
        router.swapExactTokensForTokensSplit(amountIn, minAmountOut, paths, weights, _to, block.timestamp - 1);

        vm.expectRevert('UniversalRouter: ZERO_AMOUNT_IN');
        router.swapExactTokensForTokensSplit(0, minAmountOut, paths, weights, _to, block.timestamp);

        vm.expectRevert('UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        router.swapExactTokensForTokensSplit(amountIn, minAmountOut + 1, paths, weights, _to, block.timestamp);

        router.swapExactTokensForTokensSplit(amountIn, minAmountOut, paths, weights, _to, block.timestamp);

        uint256 balanceTo1 = IERC20(routesSplit[0][routesSplit[0].length - 1].to).balanceOf(_to);
        uint256 balanceFrom1 = IERC20(routesSplit[0][0].from).balanceOf(owner);

        assertEq(amountIn, balanceFrom0 - balanceFrom1);
        assertEq(minAmountOut, balanceTo1 - balanceTo0);
        vm.stopPrank();
    }

    function testSwapExactTokensForTokensSplit10(uint8 tokenChoices, uint64 seed, uint256 amountIn) public {
        bytes[] memory paths;
        uint256[] memory weights;
        uint256 minAmountOut;
        (paths, weights, amountIn, minAmountOut) = getPathsAndWeights(tokenChoices, seed, amountIn, true, true);

        (uint256 amountOut, uint256[][] memory amountsSplit, IUniversalRouter.Route[][] memory routesSplit) = router.getAmountsOutSplit(amountIn, paths, weights);

        assertEq(amountOut,sumAmounts(amountsSplit,false));

        minAmountOut = amountOut;
        address _to = vm.addr(0x123);

        uint256 balanceTo0 = IERC20(routesSplit[0][routesSplit[0].length - 1].to).balanceOf(_to);
        uint256 balanceFrom0 = IERC20(routesSplit[0][0].from).balanceOf(owner);

        vm.startPrank(owner);
        IERC20(routesSplit[0][0].from).approve(address(router), type(uint256).max);

        bytes memory path = Path2.fromPathsAndWeightsArray(paths,weights);

        vm.expectRevert(bytes4(keccak256("Expired()")));
        router.swapExactTokensForTokens(amountIn, minAmountOut, path, _to, block.timestamp - 1);

        vm.expectRevert('UniversalRouter: ZERO_AMOUNT_IN');
        router.swapExactTokensForTokens(0, minAmountOut, path, _to, block.timestamp);

        vm.expectRevert('UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        router.swapExactTokensForTokens(amountIn, minAmountOut + 1, path, _to, block.timestamp);

        router.swapExactTokensForTokens(amountIn, minAmountOut, path, _to, block.timestamp);

        uint256 balanceTo1 = IERC20(routesSplit[0][routesSplit[0].length - 1].to).balanceOf(_to);
        uint256 balanceFrom1 = IERC20(routesSplit[0][0].from).balanceOf(owner);

        assertEq(amountIn, balanceFrom0 - balanceFrom1);
        assertEq(minAmountOut, balanceTo1 - balanceTo0);
        vm.stopPrank();
    }

    function testSwapExactTokensForTokensSplit2(uint8 tokenChoices, uint64 seed, uint256 amountOut) public {
        bytes[] memory paths;
        uint256[] memory weights;
        (paths, weights, amountOut,) = getPathsAndWeights(tokenChoices, seed, amountOut, true, false);

        uint256 amountIn;
        uint256[][] memory amountsSplit;
        IUniversalRouter.Route[][] memory routesSplit;
        (amountIn, weights, amountsSplit, routesSplit) = router.getAmountsInSplit(amountOut, paths, weights);

        address _to = vm.addr(0x123);

        uint256 balanceTo0 = IERC20(routesSplit[0][routesSplit[0].length - 1].to).balanceOf(_to);
        uint256 balanceFrom0 = IERC20(routesSplit[0][0].from).balanceOf(owner);

        vm.startPrank(owner);
        IERC20(routesSplit[0][0].from).approve(address(router), type(uint256).max);

        vm.expectRevert(bytes4(keccak256("Expired()")));
        router.swapExactTokensForTokensSplit(amountIn, amountOut, paths, weights, _to, block.timestamp - 1);

        vm.expectRevert('UniversalRouter: ZERO_AMOUNT_IN');
        router.swapExactTokensForTokensSplit(0, amountOut, paths, weights, _to, block.timestamp);

        vm.expectRevert('UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        router.swapExactTokensForTokensSplit(amountIn, amountOut * 101/100, paths, weights, _to, block.timestamp);

        router.swapExactTokensForTokensSplit(amountIn, amountOut * 99/100, paths, weights, _to, block.timestamp);

        uint256 balanceTo1 = IERC20(routesSplit[0][routesSplit[0].length - 1].to).balanceOf(_to);
        uint256 balanceFrom1 = IERC20(routesSplit[0][0].from).balanceOf(owner);

        assertEq(amountIn, balanceFrom0 - balanceFrom1);
        assertApproxEqRel(amountOut, balanceTo1 - balanceTo0, 1e16);
        vm.stopPrank();
    }

    function testSwapExactTokensForTokensSplit20(uint8 tokenChoices, uint64 seed, uint256 amountOut) public {
        bytes[] memory paths;
        uint256[] memory weights;
        (paths, weights, amountOut,) = getPathsAndWeights(tokenChoices, seed, amountOut, true, false);

        uint256 amountIn;
        uint256[][] memory amountsSplit;
        IUniversalRouter.Route[][] memory routesSplit;
        (amountIn, weights, amountsSplit, routesSplit) = router.getAmountsInSplit(amountOut, paths, weights);

        address _to = vm.addr(0x123);

        uint256 balanceTo0 = IERC20(routesSplit[0][routesSplit[0].length - 1].to).balanceOf(_to);
        uint256 balanceFrom0 = IERC20(routesSplit[0][0].from).balanceOf(owner);

        vm.startPrank(owner);
        IERC20(routesSplit[0][0].from).approve(address(router), type(uint256).max);

        bytes memory path = Path2.fromPathsAndWeightsArray(paths,weights);

        vm.expectRevert(bytes4(keccak256("Expired()")));
        router.swapExactTokensForTokens(amountIn, amountOut, path, _to, block.timestamp - 1);

        vm.expectRevert('UniversalRouter: ZERO_AMOUNT_IN');
        router.swapExactTokensForTokens(0, amountOut, path, _to, block.timestamp);

        vm.expectRevert('UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        router.swapExactTokensForTokens(amountIn, amountOut * 101/100, path, _to, block.timestamp);

        router.swapExactTokensForTokens(amountIn, amountOut * 99/100, path, _to, block.timestamp);

        uint256 balanceTo1 = IERC20(routesSplit[0][routesSplit[0].length - 1].to).balanceOf(_to);
        uint256 balanceFrom1 = IERC20(routesSplit[0][0].from).balanceOf(owner);

        assertEq(amountIn, balanceFrom0 - balanceFrom1);
        assertApproxEqRel(amountOut, balanceTo1 - balanceTo0, 1e16);
        vm.stopPrank();
    }

    function testSwapExactETHForTokensSplit(uint8 tokenChoices, uint64 seed, uint256 amountIn) public {
        bytes[] memory paths;
        uint256[] memory weights;
        uint256 minAmountOut;
        (paths, weights, amountIn, minAmountOut) = getPathsAndWeights(tokenChoices, seed, amountIn, true, true);

        IUniversalRouter.Route[] memory _routes = router.calcRoutes(paths[0], address(this));
        if(_routes[0].from != address(weth)) {
            vm.expectRevert('UniversalRouter: AMOUNT_IN_NOT_ETH');
            router.swapExactETHForTokensSplit(0, paths, weights, owner, block.timestamp);
            return;
        }

        (uint256 amountOut, uint256[][] memory amounts, IUniversalRouter.Route[][] memory routes) = router.getAmountsOutSplit(amountIn, paths, weights);

        assertEq(amountOut,sumAmounts(amounts,false));

        minAmountOut = amountOut;
        address _to = vm.addr(0x123);

        vm.expectRevert(bytes4(keccak256("Expired()")));
        router.swapExactETHForTokensSplit(minAmountOut, paths, weights, _to, block.timestamp - 1);

        vm.expectRevert('UniversalRouter: ZERO_AMOUNT_IN');
        router.swapExactETHForTokensSplit(minAmountOut, paths, weights, _to, block.timestamp);

        vm.expectRevert('UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        router.swapExactETHForTokensSplit{value: amountIn}(minAmountOut + 1, paths, weights, _to, block.timestamp);

        uint256 balanceTo0 = IERC20(routes[0][routes[0].length - 1].to).balanceOf(_to);
        uint256 balanceFrom0 = address(this).balance;

        router.swapExactETHForTokensSplit{value: amountIn}(minAmountOut, paths, weights, _to, block.timestamp);

        uint256 balanceTo1 = IERC20(routes[0][routes[0].length - 1].to).balanceOf(_to);
        uint256 balanceFrom1 = address(this).balance;

        assertEq(amountIn, balanceFrom0 - balanceFrom1);
        assertEq(minAmountOut, balanceTo1 - balanceTo0);
    }

    function testSwapExactETHForTokensSplit0(uint8 tokenChoices, uint64 seed, uint256 amountIn) public {
        bytes[] memory paths;
        uint256[] memory weights;
        uint256 minAmountOut;
        (paths, weights, amountIn, minAmountOut) = getPathsAndWeights(tokenChoices, seed, amountIn, true, true);
        bytes memory path = Path2.fromPathsAndWeightsArray(paths,weights);

        IUniversalRouter.Route[] memory _routes = router.calcRoutes(paths[0], address(this));
        if(_routes[0].from != address(weth)) {
            vm.expectRevert('UniversalRouter: AMOUNT_IN_NOT_ETH');
            router.swapExactETHForTokens(0, path, owner, block.timestamp);
            return;
        }

        (uint256 amountOut, uint256[][] memory amounts, IUniversalRouter.Route[][] memory routes) = router.getAmountsOutSplit(amountIn, paths, weights);

        assertEq(amountOut,sumAmounts(amounts,false));

        minAmountOut = amountOut;
        address _to = vm.addr(0x123);

        vm.expectRevert(bytes4(keccak256("Expired()")));
        router.swapExactETHForTokens(minAmountOut, path, _to, block.timestamp - 1);

        vm.expectRevert('UniversalRouter: ZERO_AMOUNT_IN');
        router.swapExactETHForTokens(minAmountOut, path, _to, block.timestamp);

        vm.expectRevert('UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        router.swapExactETHForTokens{value: amountIn}(minAmountOut + 1, path, _to, block.timestamp);

        uint256 balanceTo0 = IERC20(routes[0][routes[0].length - 1].to).balanceOf(_to);
        uint256 balanceFrom0 = address(this).balance;

        router.swapExactETHForTokens{value: amountIn}(minAmountOut, path, _to, block.timestamp);

        uint256 balanceTo1 = IERC20(routes[0][routes[0].length - 1].to).balanceOf(_to);
        uint256 balanceFrom1 = address(this).balance;

        assertEq(amountIn, balanceFrom0 - balanceFrom1);
        assertEq(minAmountOut, balanceTo1 - balanceTo0);
    }

    function testSwapExactTokensForETHSplit(uint8 tokenChoices, uint64 seed, uint256 amountIn) public {
        bytes[] memory paths;
        uint256[] memory weights;
        uint256 minAmountOut;
        (paths, weights, amountIn, minAmountOut) = getPathsAndWeights(tokenChoices, seed, amountIn, true, true);

        IUniversalRouter.Route[] memory _routes = router.calcRoutes(paths[0], address(this));
        if(_routes[_routes.length - 1].to != address(weth)) {
            vm.expectRevert('UniversalRouter: AMOUNT_OUT_NOT_ETH');
            router.swapExactTokensForETHSplit(0, 0, paths, weights, owner, block.timestamp);
            return;
        }

        (uint256 amountOut, uint256[][] memory amounts, IUniversalRouter.Route[][] memory routes) = router.getAmountsOutSplit(amountIn, paths, weights);

        assertEq(amountOut,sumAmounts(amounts,false));

        minAmountOut = amountOut;
        address _to = vm.addr(0x123);

        uint256 balanceTo0 = address(_to).balance;
        uint256 balanceFrom0 = IERC20(routes[0][0].from).balanceOf(owner);

        weth.deposit{value: 50e18}();

        vm.startPrank(owner);
        IERC20(routes[0][0].from).approve(address(router), type(uint256).max);

        vm.expectRevert(bytes4(keccak256("Expired()")));
        router.swapExactTokensForETHSplit(amountIn, minAmountOut, paths, weights, _to, block.timestamp - 1);

        vm.expectRevert("UniversalRouter: ZERO_AMOUNT_IN");
        router.swapExactTokensForETHSplit(0, minAmountOut, paths, weights, _to, block.timestamp);

        vm.expectRevert("UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        router.swapExactTokensForETHSplit(amountIn, minAmountOut + 1, paths, weights, _to, block.timestamp);

        router.swapExactTokensForETHSplit(amountIn, minAmountOut, paths, weights, _to, block.timestamp);

        uint256 balanceTo1 =address(_to).balance;
        uint256 balanceFrom1 = IERC20(routes[0][0].from).balanceOf(owner);

        assertEq(amountIn, balanceFrom0 - balanceFrom1);
        assertEq(minAmountOut, balanceTo1 - balanceTo0);
        vm.stopPrank();
    }

    function testSwapExactTokensForETHSplit0(uint8 tokenChoices, uint64 seed, uint256 amountIn) public {
        bytes[] memory paths;
        uint256[] memory weights;
        uint256 minAmountOut;
        (paths, weights, amountIn, minAmountOut) = getPathsAndWeights(tokenChoices, seed, amountIn, true, true);
        bytes memory path = Path2.fromPathsAndWeightsArray(paths,weights);

        IUniversalRouter.Route[] memory _routes = router.calcRoutes(paths[0], address(this));
        if(_routes[_routes.length - 1].to != address(weth)) {
            vm.expectRevert('UniversalRouter: AMOUNT_OUT_NOT_ETH');
            router.swapExactTokensForETH(0, 0, path, owner, block.timestamp);
            return;
        }

        (uint256 amountOut, uint256[][] memory amounts, IUniversalRouter.Route[][] memory routes) = router.getAmountsOutSplit(amountIn, paths, weights);

        assertEq(amountOut,sumAmounts(amounts,false));

        minAmountOut = amountOut;
        address _to = vm.addr(0x123);

        uint256 balanceTo0 = address(_to).balance;
        uint256 balanceFrom0 = IERC20(routes[0][0].from).balanceOf(owner);

        weth.deposit{value: 50e18}();

        vm.startPrank(owner);
        IERC20(routes[0][0].from).approve(address(router), type(uint256).max);

        vm.expectRevert(bytes4(keccak256("Expired()")));
        router.swapExactTokensForETH(amountIn, minAmountOut, path, _to, block.timestamp - 1);

        vm.expectRevert("UniversalRouter: ZERO_AMOUNT_IN");
        router.swapExactTokensForETH(0, minAmountOut, path, _to, block.timestamp);

        vm.expectRevert("UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT");
        router.swapExactTokensForETH(amountIn, minAmountOut + 1, path, _to, block.timestamp);

        router.swapExactTokensForETH(amountIn, minAmountOut, path, _to, block.timestamp);

        uint256 balanceTo1 =address(_to).balance;
        uint256 balanceFrom1 = IERC20(routes[0][0].from).balanceOf(owner);

        assertEq(amountIn, balanceFrom0 - balanceFrom1);
        assertEq(minAmountOut, balanceTo1 - balanceTo0);
        vm.stopPrank();
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

        vm.expectRevert(bytes4(keccak256("Expired()")));
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

        vm.expectRevert(bytes4(keccak256("Expired()")));
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

        vm.expectRevert(bytes4(keccak256("Expired()")));
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

        vm.expectRevert(bytes4(keccak256("Expired()")));
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
            amount = boundVar(amount, 1e18, 10e18);
            if(_toToken == address(wbtc)) {
                minAmount = 4400384;
            } else if(_toToken == address(dai)) {
                minAmount = 2800e18;
            } else {
                minAmount = 2800e6;
            }
        } else if(_fromToken == address(wbtc)) {
            amount = boundVar(amount, 1e6, 1e8);
            if(_toToken == address(weth)) {
                minAmount = 2e17;
            } else if(_toToken == address(dai)) {
                minAmount = 620e18;
            } else {
                minAmount = 620e6;
            }
        } else if(_fromToken == address(dai)) {
            amount = boundVar(amount, 1e18, 1000e18);
            if(_toToken == address(weth)) {
                minAmount = 313333333333333;
            } else if(_toToken == address(wbtc)) {
                minAmount = 1450;
            } else {
                minAmount = 9e5;
            }
        } else {
            amount = boundVar(amount, 1e6, 1000e6);
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

    function calcMinAmountNoSwap(uint256 amount, bytes memory path, bool isAmountIn) internal view returns(uint256, uint256) {
        IUniversalRouter.Route[] memory routes = router.calcRoutes(path, address(router));
        uint256 minAmount;
        address _fromToken = isAmountIn ? routes[0].from : routes[routes.length - 1].to;
        address _toToken = isAmountIn ? routes[routes.length - 1].to : routes[0].from;
        if(_fromToken == address(weth)) {
            amount = boundVar(amount, 0, 10e18);
            if(amount >= 1e18) {
                if(_toToken == address(wbtc)) {
                    minAmount = 4400384;
                } else if(_toToken == address(dai)) {
                    minAmount = 2800e18;
                } else {
                    minAmount = 2800e6;
                }
            }
        } else if(_fromToken == address(wbtc)) {
            amount = boundVar(amount, 0, 1e8);
            if(amount >= 1e6) {
                if(_toToken == address(weth)) {
                    minAmount = 2e17;
                } else if(_toToken == address(dai)) {
                    minAmount = 620e18;
                } else {
                    minAmount = 620e6;
                }
            }
        } else if(_fromToken == address(dai)) {
            amount = boundVar(amount, 0, 1000e18);
            if(amount >= 1e18) {
                if(_toToken == address(weth)) {
                    minAmount = 313333333333333;
                } else if(_toToken == address(wbtc)) {
                    minAmount = 1450;
                } else {
                    minAmount = 9e5;
                }
            }
        } else {
            amount = boundVar(amount, 0, 1000e6);
            if(amount >= 1e6) {
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

    function getTokensEx(address token0, address token1) internal view returns(address[] memory tokensLeft) {
        uint256 tokensSelected = 0;
        address[] memory _tokens = new address[](tokens.length);
        for(uint256 i = 0; i < tokens.length; i++) {
            if(tokens[i] != token0 && tokens[i] != token1) {
                _tokens[i] = tokens[i];
                tokensSelected++;
            }
        }
        uint256 k = 0;
        tokensLeft = new address[](tokensSelected);
        for(uint256 i = 0; i < _tokens.length; i++) {
            if(_tokens[i] != address(0)) {
                tokensLeft[k++] = _tokens[i];
            }
        }
    }

    function getProtocolIdAndFee(address token0, address token1, uint256 seed) internal view returns(uint16 protocolId, uint24 fee) {
        protocolId = uint16(random.getRandomNumber(PROTOCOL_ROUTES_COUNT, seed) + 1);
        if(protocolId == 4) {
            if(isStable(token0, token1)) {
                protocolId = 5;
            }
        } else if(protocolId == 5) {
            if(!isStable(token0, token1)) {
                protocolId = 4;
            }
        }
        fee = getProtocolFee(protocolId);
    }

    function getProtocolFee(uint16 protocolId) internal view returns(uint24 fee) {
        fee = protocolId == 6 ? poolFee1 : protocolId == 7 ? uint24(aeroCLTickSpacing): 0;
    }

    function createPaths(bytes memory path, uint128 seed, uint8 count) internal view returns(bytes[] memory paths) {
        paths = new bytes[](count + 1);
        paths[0] = path;

        address tokenIn = path.getTokenIn();
        address tokenOut = path.getTokenOut();

        for(uint256 k = 1; k < count + 1; k++) {
            address[] memory midTokens = getTokensEx(tokenIn, tokenOut);
            midTokens = random.shuffleAddresses(midTokens, seed);

            (uint16 protocolId, uint24 fee) = getProtocolIdAndFee(tokenIn,midTokens[0], seed + 10);
            bytes memory _path = abi.encodePacked(tokenIn,protocolId,fee,midTokens[0]);
            for(uint256 i = 1; i < midTokens.length; i++) {
                (protocolId, fee) = getProtocolIdAndFee(midTokens[i-1],midTokens[i], seed + i + 10);
                _path = abi.encodePacked(_path, protocolId, fee, midTokens[i]);
            }

            (protocolId, fee) = getProtocolIdAndFee(midTokens[midTokens.length-1],tokenOut, seed + midTokens.length + 10);
            paths[k] = abi.encodePacked(_path, protocolId, fee, tokenOut);
        }
    }

    function createPaths2(bytes memory path, uint128 seed) internal view returns(bytes[] memory paths) {
        paths = new bytes[](path.numPools());

        address tokenIn = path.getTokenIn();
        address tokenOut = path.getTokenOut();

        uint16 protocolId = 1;
        for(uint256 k = 0; k < path.numPools(); k++) {
            address[] memory midTokens = getTokensEx(tokenIn, tokenOut);
            midTokens = random.shuffleAddresses(midTokens, seed);

            uint24 fee = getProtocolFee(protocolId);
            bytes memory _path = abi.encodePacked(tokenIn,protocolId,fee,midTokens[0]);
            for(uint256 i = 1; i < midTokens.length; i++) {
                _path = abi.encodePacked(_path, protocolId, fee, midTokens[i]);
            }

            paths[k] = abi.encodePacked(_path, protocolId, fee, tokenOut);

            protocolId++;
            if(protocolId == 4 || protocolId == 5) {
                protocolId = 6;
            }
        }
    }

    function createPath(uint8 tokenChoices, uint128 seed) internal view returns(bytes memory) {
        address[] memory _tokens = tokens;
        _tokens = random.shuffleAddresses(_tokens, seed);
        _tokens = getTokens(tokenChoices, _tokens);

        bytes memory _path = abi.encodePacked(_tokens[0]);
        for(uint256 i = 1; i < _tokens.length; i++) {
            (uint16 protocolId, uint24 fee) = getProtocolIdAndFee(_tokens[i-1],_tokens[i], seed + i + 10);
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
        vm.expectRevert('INVALID_PATH');
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b';
        vm.expectRevert('INVALID_PATH');
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470bff';
        vm.expectRevert('INVALID_PATH');
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8';
        vm.expectRevert('INVALID_PATH');
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000b';
        vm.expectRevert('INVALID_PATH');
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff00';
        vm.expectRevert('INVALID_PATH');
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8F62849F9A0B5Bf2913b396098F7c7019b51A820a';
        vm.expectRevert('UniversalRouter: PROTOCOL_ROUTE_NOT_SET');
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A90001000bb82e234DAe75C793f67A35089C9d99245E1C58470b0001000bb8F62849F9A0B5Bf2913b396098F7c7019b51A820a';
        router.calcRoutes(path, address(this));

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A90001000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8F62849F9A0B5Bf2913b396098F7c7019b51A82';
        vm.expectRevert('INVALID_PATH');
        router.calcRoutes(path, address(this));
    }

    function testGetAmountsOutErrors() public {
        bytes memory path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b';

        vm.expectRevert('UniversalRouter: PROTOCOL_ROUTE_NOT_SET');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C5847';
        vm.expectRevert('INVALID_PATH');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b';
        vm.expectRevert('INVALID_PATH');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470bff';
        vm.expectRevert('INVALID_PATH');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8';
        vm.expectRevert('INVALID_PATH');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000b';
        vm.expectRevert('INVALID_PATH');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff00';
        vm.expectRevert('INVALID_PATH');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8F62849F9A0B5Bf2913b396098F7c7019b51A820a';
        vm.expectRevert('UniversalRouter: PROTOCOL_ROUTE_NOT_SET');
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A90001000bb82e234DAe75C793f67A35089C9d99245E1C58470b0001000bb8F62849F9A0B5Bf2913b396098F7c7019b51A820a';
        router.getAmountsOut(1e18, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A90001000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8F62849F9A0B5Bf2913b396098F7c7019b51A82';
        vm.expectRevert('INVALID_PATH');
        router.getAmountsOut(1e18, path);
    }

    function testGetAmountsInErrors() public {
        bytes memory path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b';

        vm.expectRevert('UniversalRouter: PROTOCOL_ROUTE_NOT_SET');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C5847';
        vm.expectRevert('INVALID_PATH');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b';
        vm.expectRevert('INVALID_PATH');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470bff';
        vm.expectRevert('INVALID_PATH');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8';
        vm.expectRevert('INVALID_PATH');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000b';
        vm.expectRevert('INVALID_PATH');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff00';
        vm.expectRevert('INVALID_PATH');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900ff000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8F62849F9A0B5Bf2913b396098F7c7019b51A820a';
        vm.expectRevert('UniversalRouter: PROTOCOL_ROUTE_NOT_SET');
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A90001000bb82e234DAe75C793f67A35089C9d99245E1C58470b0001000bb8F62849F9A0B5Bf2913b396098F7c7019b51A820a';
        router.getAmountsIn(1e6, path);

        path = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A90001000bb82e234DAe75C793f67A35089C9d99245E1C58470b00ff000bb8F62849F9A0B5Bf2913b396098F7c7019b51A82';
        vm.expectRevert('INVALID_PATH');
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

    function testPathAndWeightsArray() public {
        bytes memory tag25bytes = hex'00000000000000000000000000000000000000000000000000';
        uint64 weight1 = 4e16;
        uint64 weight2 = 2e16;
        bytes memory path0 = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e5831';
        bytes memory path1 = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e5831000100010076991314cEE341ebE37e6E2712cb04F5d56dE355';
        bytes memory path2 = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e5831000100010076991314cEE341ebE37e6E2712cb04F5d56dE3550001000100F6D9C101ceeA72655A13a8Cf1C88c1949Ed399bc';

        bytes memory path = abi.encodePacked(weight1,path0);
        path = abi.encodePacked(path,tag25bytes,weight1,path1);
        path = abi.encodePacked(path,tag25bytes,weight2,path2);

        (bytes[] memory paths, uint256[] memory weights)= path.toPathsAndWeightsArray();

        assertEq(paths.length,3);
        assertEq(paths.length,weights.length);
        assertEq(paths[0],path0);
        assertEq(paths[1],path1);
        assertEq(paths[2],path2);
        assertEq(weights[0],weight1);
        assertEq(weights[1],weight1);
        assertEq(weights[2],weight2);

        bytes memory combinedPaths = Path2.fromPathsAndWeightsArray(paths, weights);
        assertEq(combinedPaths,path);
    }

    function testValidatePathsAndWeights() public {
        bytes[] memory paths = new bytes[](0);
        uint256[] memory weights = new uint256[](2);

        vm.expectRevert("UniversalRouter: MISSING_PATHS");
        router.validatePathsAndWeights(paths, weights, 2);

        paths = new bytes[](1);
        vm.expectRevert("UniversalRouter: INVALID_WEIGHTS");
        router.validatePathsAndWeights(paths, weights, 2);

        paths = new bytes[](3);
        vm.expectRevert("UniversalRouter: INVALID_WEIGHTS");
        router.validatePathsAndWeights(paths, weights, 2);

        paths = new bytes[](2);
        vm.expectRevert("INVALID_PATH");
        router.validatePathsAndWeights(paths, weights, 2);

        paths[0] = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f40c880f6761f1af8d9aa9c466984b80dab9a8c9e8';
        vm.expectRevert("UniversalRouter: INVALID_PATH_TOKENS");
        router.validatePathsAndWeights(paths, weights, 2);

        paths[0] = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab1';
        vm.expectRevert("UniversalRouter: AMOUNT_IN_NOT_ETH");
        router.validatePathsAndWeights(paths, weights, 0);

        paths[0] = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab1';
        vm.expectRevert("UniversalRouter: AMOUNT_OUT_NOT_ETH");
        router.validatePathsAndWeights(paths, weights, 1);

        paths[0] = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab1';
        vm.expectRevert("INVALID_PATH");
        router.validatePathsAndWeights(paths, weights, 2);

        paths[0] = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab100010001f4af88d065e77c8cc2239327c5edb3a432268e5831';
        paths[1] = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab1';
        vm.expectRevert("UniversalRouter: INVALID_PATH_TOKENS");
        router.validatePathsAndWeights(paths, weights, 2);

        paths[0] = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab1';
        paths[1] = hex'0c880f6761f1af8d9aa9c466984b80dab9a8c9e80001000bb882af49447d8a07e3bd95bd0d56f35241523fbab1';
        vm.expectRevert('UniversalRouter: INVALID_WEIGHTS');
        router.validatePathsAndWeights(paths, weights, 2);

        weights[0] = 2e17;
        weights[1] = 8e17 + 1;
        vm.expectRevert('UniversalRouter: INVALID_WEIGHTS');
        router.validatePathsAndWeights(paths, weights, 2);

        weights[1] = 8e17 - 1;
        router.validatePathsAndWeights(paths, weights, 2);

        weights[0] = 2e17 + 1;
        router.validatePathsAndWeights(paths, weights, 2);

        weights[1] = 8e17;
        vm.expectRevert('UniversalRouter: INVALID_WEIGHTS');
        router.validatePathsAndWeights(paths, weights, 2);

        weights[0] = 2e17;
        weights[1] = 8e17;
        router.validatePathsAndWeights(paths, weights, 2);

        paths[0] = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A90001000bb882af49447d8a07e3bd95bd0d56f35241523fbab1';
        vm.expectRevert('UniversalRouter: INVALID_PATH_TOKENS');
        router.validatePathsAndWeights(paths, weights, 0);

        paths[0] = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A90001000bb882af49447d8a07e3bd95bd0d56f35241523fbab1';
        paths[1] = hex'5991A2dF15A8F6A256D3Ec51E99254Cd3fb576A900010001f4af88d065e77c8cc2239327c5edb3a432268e58310001000bb882af49447d8a07e3bd95bd0d56f35241523fbab1';
        router.validatePathsAndWeights(paths, weights, 0);

        paths[0] = hex'af49447d8a07e3bd95bd0d56f35241523fbab10001000bb8825991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9';
        paths[1] = hex'af49447d8a07e3bd95bd0d56f35241523fbab10001000bb8825991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9';
        vm.expectRevert("UniversalRouter: AMOUNT_IN_NOT_ETH");
        router.validatePathsAndWeights(paths, weights, 0);

        paths[0] = hex'af49447d8a07e3bd95bd0d56f35241523fbab10001000bb8825991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9';
        paths[1] = hex'af49447d8a07e3bd95bd0d56f35241523fbab10001000bb8825991A2dF15A8F6A256D3Ec51E99254Cd3fb576A9';
        router.validatePathsAndWeights(paths, weights, 1);
    }

    function testCalcPathFee2() public {
        bytes memory pathUsdcToWeth = abi.encodePacked(address(usdc), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(weth));
        uint256 pathFee = router.calcPathFee(pathUsdcToWeth);
        assertEq(pathFee, 5991);

        bytes memory pathWethToUsdc = abi.encodePacked(address(weth), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(usdc));
        pathFee = router.calcPathFee(pathWethToUsdc);
        assertEq(pathFee, 5991);

        bytes memory pathWethToDai = abi.encodePacked(address(weth), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(usdc), uint16(6), poolFee1, address(dai));
        pathFee = router.calcPathFee(pathWethToDai);
        assertEq(pathFee, 15932);

        pathWethToDai = abi.encodePacked(address(weth), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(usdc), uint16(5), poolFee1, address(dai));
        pathFee = router.calcPathFee(pathWethToDai);
        assertEq(pathFee, 6489);
    }

    function testCalcPathFeeSplit() public {
        uint256[] memory weights = new uint256[](3);
        weights[0] = 1e18 / uint256(3);
        weights[1] = 1e18 / uint256(3);
        weights[1] = 1e18 / uint256(3);

        bytes[] memory pathsUsdcToWeth = new bytes[](3);
        pathsUsdcToWeth[0] = abi.encodePacked(address(usdc), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(weth));
        pathsUsdcToWeth[1] = abi.encodePacked(address(usdc), uint16(2), poolFee1, address(wbtc), uint16(2), poolFee1, address(weth));
        pathsUsdcToWeth[2] = abi.encodePacked(address(usdc), uint16(3), poolFee1, address(wbtc), uint16(3), poolFee1, address(weth));
        uint256 pathFee = router.calcPathFeeSplit(pathsUsdcToWeth, weights);
        bytes memory path = Path2.fromPathsAndWeightsArray(pathsUsdcToWeth,weights);
        assertEq(pathFee, 5988);
        assertEq(pathFee,router.calcPathFee(path));

        bytes[] memory pathsWethToUsdc = new bytes[](3);
        pathsWethToUsdc[0] = abi.encodePacked(address(weth), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(usdc));
        pathsWethToUsdc[1] = abi.encodePacked(address(weth), uint16(2), poolFee1, address(wbtc), uint16(2), poolFee1, address(usdc));
        pathsWethToUsdc[2] = abi.encodePacked(address(weth), uint16(3), poolFee1, address(wbtc), uint16(3), poolFee1, address(usdc));
        pathFee = router.calcPathFeeSplit(pathsWethToUsdc, weights);
        path = Path2.fromPathsAndWeightsArray(pathsWethToUsdc,weights);
        assertEq(pathFee, 5988);
        assertEq(pathFee,router.calcPathFee(path));

        bytes[] memory pathsWethToDai = new bytes[](3);
        pathsWethToDai[0] = abi.encodePacked(address(weth), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(usdc), uint16(6), poolFee1, address(dai));
        pathsWethToDai[1] = abi.encodePacked(address(weth), uint16(2), poolFee1, address(wbtc), uint16(2), poolFee1, address(usdc), uint16(6), poolFee1, address(dai));
        pathsWethToDai[2] = abi.encodePacked(address(weth), uint16(3), poolFee1, address(wbtc), uint16(3), poolFee1, address(usdc), uint16(6), poolFee1, address(dai));
        pathFee = router.calcPathFeeSplit(pathsWethToDai, weights);
        path = Path2.fromPathsAndWeightsArray(pathsWethToDai,weights);
        assertEq(pathFee, 15930);
        assertEq(pathFee,router.calcPathFee(path));

        pathsWethToDai[0] = abi.encodePacked(address(weth), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(usdc), uint16(5), poolFee1, address(dai));
        pathsWethToDai[1] = abi.encodePacked(address(weth), uint16(2), poolFee1, address(wbtc), uint16(2), poolFee1, address(usdc), uint16(5), poolFee1, address(dai));
        pathsWethToDai[2] = abi.encodePacked(address(weth), uint16(3), poolFee1, address(wbtc), uint16(3), poolFee1, address(usdc), uint16(5), poolFee1, address(dai));
        pathFee = router.calcPathFeeSplit(pathsWethToDai, weights);
        path = Path2.fromPathsAndWeightsArray(pathsWethToDai,weights);
        assertEq(pathFee, 6486);
        assertEq(pathFee,router.calcPathFee(path));

        weights = new uint256[](2);
        weights[0] = 1e18 / uint256(2);
        weights[1] = 1e18 / uint256(2);
        pathsWethToDai = new bytes[](2);
        pathsWethToDai[0] = abi.encodePacked(address(weth), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(usdc), uint16(6), poolFee1, address(dai));
        pathsWethToDai[1] = abi.encodePacked(address(weth), uint16(2), poolFee1, address(wbtc), uint16(2), poolFee1, address(usdc), uint16(5), poolFee1, address(dai));
        pathFee = router.calcPathFeeSplit(pathsWethToDai, weights);
        path = Path2.fromPathsAndWeightsArray(pathsWethToDai,weights);
        assertEq(pathFee, 11210); //~(15930 + 6486) / 2
        assertEq(pathFee,router.calcPathFee(path));
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

    function testPathFeesSplit(uint8 tokenChoices, uint64 seed, uint256 amountIn) public {
        bytes[] memory paths;
        uint256[] memory weights;
        uint256 minAmountOut;
        (paths, weights, amountIn, minAmountOut) = getPathsAndWeights(tokenChoices, seed, amountIn, true, true);


        IUniversalRouter.Route[] memory _routes = router.calcRoutes(paths[0], address(this));
        amountIn = getMinAmountIn(_routes[0].from);
        uint256 amountOut = router.quoteSplit(amountIn,paths,weights);

        uint256 pathFee = router.calcPathFeeSplit(paths,weights);
        uint256 amountOutPostFees = amountOut - amountOut * pathFee / 1e6;

        vm.startPrank(owner);

        uint256 balanceTo0 = IERC20(_routes[_routes.length - 1].to).balanceOf(owner);
        console.log("balanceTo0:",balanceTo0);
        uint256 balanceFrom0 = IERC20(_routes[0].from).balanceOf(owner);

        IERC20(_routes[0].from).approve(address(router), type(uint256).max);

        router.swapExactTokensForTokensSplit(amountIn, 0, paths, weights, owner, block.timestamp);

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
        deltaUSDC = boundVar(deltaUSDC, 10e6, 1_000e6);
        deltaWETH = boundVar(deltaWETH, 1e16, 10e18);

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

    function testExternalCallSwap2(uint256 deltaUSDC, uint256 deltaWETH, bool isBuyWeth) public {
        deltaUSDC = boundVar(deltaUSDC, 10e6, 1_000e6);
        deltaWETH = boundVar(deltaWETH, 1e16, 10e18);

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

    function testExternalCallSwapSplit(uint256 deltaUSDC, uint256 deltaWETH, bool isBuyWeth) public {
        deltaUSDC = boundVar(deltaUSDC, 10e6, 1_000e6);
        deltaWETH = boundVar(deltaWETH, 1e16, 10e18);

        bytes memory multiPathUsdcToWeth;
        bytes memory multiPathWethToUsdc;

        {
            bytes memory tag25bytes = hex'00000000000000000000000000000000000000000000000000';
            uint64 weight1 = 4e17;
            uint64 weight2 = 3e17;
            uint64 weight3 = 3e17;

            bytes memory pathUsdcToWeth1 = abi.encodePacked(address(usdc), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(weth));
            bytes memory pathUsdcToWeth2 = abi.encodePacked(address(usdc), uint16(2), poolFee1, address(wbtc), uint16(2), poolFee1, address(weth));
            bytes memory pathUsdcToWeth3 = abi.encodePacked(address(usdc), uint16(3), poolFee1, address(wbtc), uint16(3), poolFee1, address(weth));
            multiPathUsdcToWeth = abi.encodePacked(weight1,pathUsdcToWeth1,tag25bytes,weight2,pathUsdcToWeth2,tag25bytes,weight3,pathUsdcToWeth3);

            bytes memory pathWethToUsdc1 = abi.encodePacked(address(weth), uint16(1), poolFee1, address(wbtc), uint16(1), poolFee1, address(usdc));
            bytes memory pathWethToUsdc2 = abi.encodePacked(address(weth), uint16(2), poolFee1, address(wbtc), uint16(2), poolFee1, address(usdc));
            bytes memory pathWethToUsdc3 = abi.encodePacked(address(weth), uint16(3), poolFee1, address(wbtc), uint16(3), poolFee1, address(usdc));
            multiPathWethToUsdc = abi.encodePacked(weight1,pathWethToUsdc1,tag25bytes,weight2,pathWethToUsdc2,tag25bytes,weight3,pathWethToUsdc3);/**/
        }

        UniversalRouter.ExternalCallData memory data;

        if (isBuyWeth) {
            data = IRouterExternalCallee.ExternalCallData({
                amountIn: deltaUSDC,
                minAmountOut: 0,
                deadline: type(uint256).max,
                tokenId: 100,
                path: multiPathUsdcToWeth
            });
        } else {
            data = IRouterExternalCallee.ExternalCallData({
                amountIn: deltaWETH,
                minAmountOut: 0,
                deadline: type(uint256).max,
                tokenId: 100,
                path: multiPathWethToUsdc
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

        uint256 amountOut = calcAmountOutSplit(data.amountIn, data.path);
        // Avoid stack-too-deep
        {
            vm.expectEmit(true,true,true,false);
            emit ExternalCallSwap(vm.addr(1), address(this), data.tokenId, isBuyWeth ? address(usdc) : address(weth), isBuyWeth ? address(weth) : address(usdc), data.amountIn, amountOut);
            router.externalCall(vm.addr(1), amounts, 0, abi.encode(data));
        }

        if(isBuyWeth) {
            assertEq(usdc.balanceOf(address(this)), balanceUSDC);
            assertGt(weth.balanceOf(address(this)), balanceWETH);
            assertApproxEqRel(weth.balanceOf(address(this)) - balanceWETH,amountOut + deltaWETH,1e15);
        } else {
            assertGt(usdc.balanceOf(address(this)), balanceUSDC);
            assertEq(weth.balanceOf(address(this)), balanceWETH);
            assertApproxEqRel(usdc.balanceOf(address(this)) - balanceUSDC,amountOut + deltaUSDC,1e15);
        }
        assertEq(usdc.balanceOf(address(router)), 0);
        assertEq(weth.balanceOf(address(router)), 0);
    }

    function calcAmountOutSplit(uint256 amountIn, bytes memory path) internal returns(uint256 amountOut) {
        (bytes[] memory paths, uint256[] memory weights) = path.toPathsAndWeightsArray();
        (amountOut,,) = router.getAmountsOutSplit(amountIn, paths, weights);
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
