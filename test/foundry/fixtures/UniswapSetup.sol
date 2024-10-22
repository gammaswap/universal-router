// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol';
import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-periphery/contracts/interfaces/IPoolInitializer.sol';
import '@uniswap/swap-router-contracts/contracts/interfaces/IQuoterV2.sol';

import '@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapFactory.sol';
import '@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapPair.sol';
import '@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapRouter02.sol';
import '@gammaswap/v1-core/contracts/GammaPoolFactory.sol';

import '../../../contracts/interfaces/external/IAeroCLPool.sol';
import '../../../contracts/interfaces/external/IAeroCLPoolFactory.sol';
import '../../../contracts/interfaces/external/IAeroPoolFactory.sol';
import '../../../contracts/interfaces/external/IAeroPool.sol';
import '../../../contracts/test/IAeroCLPositionManager.sol';
import '../../../contracts/test/IAeroPositionManagerMintable.sol';
import '../../../contracts/test/IAeroRouter.sol';
import '../../../contracts/test/IAeroToken.sol';
import '../../../contracts/test/ICLGaugeFactory.sol';
import '../../../contracts/test/IPositionManagerMintable.sol';
import './TokensSetup.sol';

contract UniswapSetup is TokensSetup {

    IDeltaSwapFactory public uniFactory;
    IDeltaSwapRouter02 public uniRouter;
    IDeltaSwapPair public wethUsdcPool;
    IDeltaSwapPair public wethUsdtPool;
    IDeltaSwapPair public wethDaiPool;
    IDeltaSwapPair public wbtcWethPool;
    IDeltaSwapPair public wbtcUsdcPool;
    IDeltaSwapPair public wbtcUsdtPool;
    IDeltaSwapPair public wbtcDaiPool;
    IDeltaSwapPair public usdtUsdcPool;
    IDeltaSwapPair public daiUsdcPool;
    IDeltaSwapPair public daiUsdtPool;

    bytes32 public cfmmHash;
    address public cfmmFactory;

    IDeltaSwapFactory public sushiFactory;
    IDeltaSwapRouter02 public sushiRouter;
    IDeltaSwapPair public sushiWethUsdcPool;
    IDeltaSwapPair public sushiWethUsdtPool;
    IDeltaSwapPair public sushiWethDaiPool;
    IDeltaSwapPair public sushiWbtcWethPool;
    IDeltaSwapPair public sushiWbtcUsdcPool;
    IDeltaSwapPair public sushiWbtcUsdtPool;
    IDeltaSwapPair public sushiWbtcDaiPool;
    IDeltaSwapPair public sushiUsdtUsdcPool;
    IDeltaSwapPair public sushiDaiUsdcPool;
    IDeltaSwapPair public sushiDaiUsdtPool;

    bytes32 public sushiCfmmHash; // DeltaSwapPair init_code_hash
    address public sushiCfmmFactory;

    GammaPoolFactory public gsFactory;
    IDeltaSwapFactory public dsFactory;
    IDeltaSwapRouter02 public dsRouter;
    IDeltaSwapPair public dsWethUsdcPool;
    IDeltaSwapPair public dsWethUsdtPool;
    IDeltaSwapPair public dsWethDaiPool;
    IDeltaSwapPair public dsWbtcWethPool;
    IDeltaSwapPair public dsWbtcUsdcPool;
    IDeltaSwapPair public dsWbtcUsdtPool;
    IDeltaSwapPair public dsWbtcDaiPool;
    IDeltaSwapPair public dsUsdtUsdcPool;
    IDeltaSwapPair public dsDaiUsdcPool;
    IDeltaSwapPair public dsDaiUsdtPool;

    bytes32 public dsCfmmHash; // DeltaSwapPair init_code_hash
    address public dsCfmmFactory;

    IUniswapV3Factory public uniFactoryV3;
    IQuoterV2 public quoter;
    IUniswapV3Pool public wethUsdcPoolV3;
    IUniswapV3Pool public wethUsdtPoolV3;
    IUniswapV3Pool public wethDaiPoolV3;
    IUniswapV3Pool public wbtcWethPoolV3;
    IUniswapV3Pool public wbtcUsdcPoolV3;
    IUniswapV3Pool public wbtcUsdtPoolV3;
    IUniswapV3Pool public wbtcDaiPoolV3;
    IUniswapV3Pool public usdtUsdcPoolV3;
    IUniswapV3Pool public daiUsdcPoolV3;
    IUniswapV3Pool public daiUsdtPoolV3;

    uint24 public immutable poolFee1 = 10000;    // fee 1%
    uint24 public immutable poolFee2 = 500;    // fee 0.05%
    uint160 public immutable wethUsdcSqrtPriceX96 = 4339505179874779489431521;  // 1 WETH ~ 3000 USDC
    uint160 public immutable wethDaiSqrtPriceX96 = 4332395497648170000000000000000;  // 1 WETH ~ 3000 DAI
    uint160 public immutable wbtcWethSqrtPriceX96 = 36694310972870000000000000000000000;
    uint160 public immutable wbtcUsdcSqrtPriceX96 = 2018932870620950000000000000000; // 1 WBTC ~ 65000 USDC
    uint160 public immutable wbtcDaiSqrtPriceX96 = 2017398273592530000000000000000000000; // 1 WBTC ~ 65000 DAI
    uint160 public immutable usdtUsdcSqrtPriceX96 = 79288338342225900000000000000;
    uint160 public immutable daiUsdcSqrtPriceX96 = 79288429891486500000000;

    IAeroPoolFactory public aeroFactory;
    IAeroRouter public aeroRouter;
    IAeroPool public aeroWethUsdcPool;
    IAeroPool public aeroWethUsdtPool;
    IAeroPool public aeroWethDaiPool;
    IAeroPool public aeroWbtcWethPool;
    IAeroPool public aeroWbtcUsdcPool;
    IAeroPool public aeroWbtcUsdtPool;
    IAeroPool public aeroWbtcDaiPool;
    IAeroPool public aeroUsdtUsdcPool;
    IAeroPool public aeroDaiUsdcPool;
    IAeroPool public aeroDaiUsdtPool;
    address public aeroVoter;

    IAeroCLPoolFactory public aeroCLFactory;
    address public aeroCLQuoter;
    int24 public aeroCLTickSpacing = 100;
    IAeroCLPool public aeroCLWethUsdcPool;
    IAeroCLPool public aeroCLWethUsdtPool;
    IAeroCLPool public aeroCLWethDaiPool;
    IAeroCLPool public aeroCLWbtcWethPool;
    IAeroCLPool public aeroCLWbtcUsdcPool;
    IAeroCLPool public aeroCLWbtcUsdtPool;
    IAeroCLPool public aeroCLWbtcDaiPool;
    IAeroCLPool public aeroCLUsdtUsdcPool;
    IAeroCLPool public aeroCLDaiUsdcPool;
    IAeroCLPool public aeroCLDaiUsdtPool;

    function initUniswapV3(address owner) public {
        bytes memory factoryBytecode = abi.encodePacked(vm.getCode("./node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json"));
        assembly {
            sstore(uniFactoryV3.slot, create(0, add(factoryBytecode, 0x20), mload(factoryBytecode)))
        }
        // uniFactoryV3.enableFeeAmount(100, 1);

        address tickLens = createContractFromBytecode("./node_modules/@uniswap/v3-periphery/artifacts/contracts/lens/TickLens.sol/TickLens.json");
        address nftDescriptorLib = createContractFromBytecode("./node_modules/@uniswap/v3-periphery/artifacts/contracts/libraries/NFTDescriptor.sol/NFTDescriptor.json");
        address nftPositionManager = createContractFromBytecodeWithArgs("./node_modules/@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json",
            abi.encode(address(uniFactoryV3), address(weth), address(0)));

        bytes memory quoterBytecode = abi.encodePacked(vm.getCode("./node_modules/@uniswap/swap-router-contracts/artifacts/contracts/lens/QuoterV2.sol/QuoterV2.json"), abi.encode(address(uniFactoryV3), address(weth)));
        assembly {
            sstore(quoter.slot, create(0, add(quoterBytecode, 0x20), mload(quoterBytecode)))
        }

        wethUsdcPoolV3 = IUniswapV3Pool(
            IPoolInitializer(nftPositionManager).createAndInitializePoolIfNecessary(address(weth), address(usdc), poolFee1, wethUsdcSqrtPriceX96)
        );
        wethUsdtPoolV3 = IUniswapV3Pool(
            IPoolInitializer(nftPositionManager).createAndInitializePoolIfNecessary(address(weth), address(usdt), poolFee1, wethUsdcSqrtPriceX96)
        );
        wethDaiPoolV3 = IUniswapV3Pool(
            IPoolInitializer(nftPositionManager).createAndInitializePoolIfNecessary(address(weth), address(dai), poolFee1, wethDaiSqrtPriceX96)
        );
        wbtcWethPoolV3 = IUniswapV3Pool(
            IPoolInitializer(nftPositionManager).createAndInitializePoolIfNecessary(address(wbtc), address(weth), poolFee1, wbtcWethSqrtPriceX96)
        );
        wbtcUsdcPoolV3 = IUniswapV3Pool(
            IPoolInitializer(nftPositionManager).createAndInitializePoolIfNecessary(address(wbtc), address(usdc), poolFee1, wbtcUsdcSqrtPriceX96)
        );
        wbtcUsdtPoolV3 = IUniswapV3Pool(
            IPoolInitializer(nftPositionManager).createAndInitializePoolIfNecessary(address(wbtc), address(usdt), poolFee1, wbtcUsdcSqrtPriceX96)
        );
        wbtcDaiPoolV3 = IUniswapV3Pool(
            IPoolInitializer(nftPositionManager).createAndInitializePoolIfNecessary(address(wbtc), address(dai), poolFee1, wbtcDaiSqrtPriceX96)
        );
        usdtUsdcPoolV3 = IUniswapV3Pool(
            IPoolInitializer(nftPositionManager).createAndInitializePoolIfNecessary(address(usdt), address(usdc), poolFee1, usdtUsdcSqrtPriceX96)
        );
        daiUsdcPoolV3 = IUniswapV3Pool(
            IPoolInitializer(nftPositionManager).createAndInitializePoolIfNecessary(address(dai), address(usdc), poolFee1, daiUsdcSqrtPriceX96)
        );
        daiUsdtPoolV3 = IUniswapV3Pool(
            IPoolInitializer(nftPositionManager).createAndInitializePoolIfNecessary(address(dai), address(usdt), poolFee1, daiUsdcSqrtPriceX96)
        );

        weth.mint(owner, 120);
        usdc.mint(owner, 350_000);
        weth.mint(owner, 890);
        usdt.mint(owner, 2_700_000);
        weth.mint(owner, 120);
        dai.mint(owner, 350_000);
        weth.mint(owner, 220);
        wbtc.mint(owner, 11);
        wbtc.mint(owner, 11);
        usdc.mint(owner, 660_000);
        wbtc.mint(owner, 11);
        usdt.mint(owner, 660_000);
        wbtc.mint(owner, 11);
        dai.mint(owner, 660_000);
        usdc.mint(owner, 660_000);
        usdt.mint(owner, 660_000);
        usdc.mint(owner, 660_000);
        dai.mint(owner, 660_000);
        usdt.mint(owner, 660_000);
        dai.mint(owner, 660_000);

        vm.startPrank(owner);

        weth.approve(nftPositionManager, type(uint256).max);
        usdc.approve(nftPositionManager, type(uint256).max);
        usdt.approve(nftPositionManager, type(uint256).max);
        wbtc.approve(nftPositionManager, type(uint256).max);
        dai.approve(nftPositionManager, type(uint256).max);

        addLiquidityV3(nftPositionManager, address(weth), address(usdc), poolFee1, 115594502247137145239, 345648123455);
        addLiquidityV3(nftPositionManager, address(weth), address(usdt), poolFee1, 887209737429288199534, 2680657431182);
        addLiquidityV3(nftPositionManager, address(weth), address(dai), poolFee1, 115594502247137145239, 345648123455000000000000);
        addLiquidityV3(nftPositionManager, address(wbtc), address(weth), poolFee1, 1012393293, 217378372286812000000);
        addLiquidityV3(nftPositionManager, address(wbtc), address(usdc), poolFee1, 1012393293, 658055640487);
        addLiquidityV3(nftPositionManager, address(wbtc), address(usdt), poolFee1, 1013393293, 659055640487);
        addLiquidityV3(nftPositionManager, address(wbtc), address(dai), poolFee1, 1011393293, 657055640487000000000000);
        addLiquidityV3(nftPositionManager, address(usdt), address(usdc), poolFee1, 658055640487, 659055640487);
        addLiquidityV3(nftPositionManager, address(dai), address(usdc), poolFee1, 657055640487000000000000, 658055640487);
        addLiquidityV3(nftPositionManager, address(dai), address(usdt), poolFee1, 657055640487000000000000, 656055640487);

        vm.stopPrank();
    }

    function initUniswap(address owner) public {
        // Let's do the same thing with `getCode`
        //bytes memory args = abi.encode(arg1, arg2);
        bytes memory factoryArgs = abi.encode(owner);
        bytes memory factoryBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/UniswapV2Factory.json"), factoryArgs);
        address factoryAddress;
        assembly {
            factoryAddress := create(0, add(factoryBytecode, 0x20), mload(factoryBytecode))
        }

        bytes memory routerArgs = abi.encode(factoryAddress, weth);
        bytes memory routerBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/UniswapV2Router02.json"), routerArgs);
        address routerAddress;
        assembly {
            routerAddress := create(0, add(routerBytecode, 0x20), mload(routerBytecode))
        }

        uniFactory = IDeltaSwapFactory(factoryAddress);
        uniRouter = IDeltaSwapRouter02(routerAddress);

        cfmmHash = hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f'; // UniV2Pair init_code_hash
        cfmmFactory = address(0);

        wethUsdcPool = IDeltaSwapPair(uniFactory.createPair(address(weth), address(usdc)));
        wethUsdtPool = IDeltaSwapPair(uniFactory.createPair(address(weth), address(usdt)));
        wethDaiPool = IDeltaSwapPair(uniFactory.createPair(address(weth), address(dai)));
        wbtcWethPool = IDeltaSwapPair(uniFactory.createPair(address(wbtc), address(weth)));
        wbtcUsdcPool = IDeltaSwapPair(uniFactory.createPair(address(wbtc), address(usdc)));
        wbtcUsdtPool = IDeltaSwapPair(uniFactory.createPair(address(wbtc), address(usdt)));
        wbtcDaiPool = IDeltaSwapPair(uniFactory.createPair(address(wbtc), address(dai)));
        usdtUsdcPool = IDeltaSwapPair(uniFactory.createPair(address(usdt), address(usdc)));
        daiUsdcPool = IDeltaSwapPair(uniFactory.createPair(address(dai), address(usdc)));
        daiUsdtPool = IDeltaSwapPair(uniFactory.createPair(address(dai), address(usdt)));

        weth.mint(owner, 120);
        usdc.mint(owner, 350_000);
        weth.mint(owner, 890);
        usdt.mint(owner, 2_700_000);
        weth.mint(owner, 120);
        dai.mint(owner, 350_000);
        weth.mint(owner, 220);
        wbtc.mint(owner, 11);
        wbtc.mint(owner, 11);
        usdc.mint(owner, 660_000);
        wbtc.mint(owner, 11);
        usdt.mint(owner, 660_000);
        wbtc.mint(owner, 11);
        dai.mint(owner, 660_000);
        usdc.mint(owner, 660_000);
        usdt.mint(owner, 660_000);
        usdc.mint(owner, 660_000);
        dai.mint(owner, 660_000);
        usdt.mint(owner, 660_000);
        dai.mint(owner, 660_000);

        vm.startPrank(owner);

        weth.approve(address(uniRouter), type(uint256).max);
        usdc.approve(address(uniRouter), type(uint256).max);
        usdt.approve(address(uniRouter), type(uint256).max);
        wbtc.approve(address(uniRouter), type(uint256).max);
        dai.approve(address(uniRouter), type(uint256).max);

        uniRouter.addLiquidity(address(weth), address(usdc), 115594502247137145239, 345648123455, 0, 0, owner, type(uint256).max);
        uniRouter.addLiquidity(address(weth), address(usdt), 887209737429288199534, 2680657431182, 0, 0, owner, type(uint256).max);
        uniRouter.addLiquidity(address(weth), address(dai), 115594502247137145239, 345648123455000000000000, 0, 0, owner, type(uint256).max);
        uniRouter.addLiquidity(address(wbtc), address(weth), 1012393293, 217378372286812000000, 0, 0, owner, type(uint256).max);
        uniRouter.addLiquidity(address(wbtc), address(usdc), 1012393293, 658055640487, 0, 0, owner, type(uint256).max);
        uniRouter.addLiquidity(address(wbtc), address(usdt), 1013393293, 659055640487, 0, 0, owner, type(uint256).max);
        uniRouter.addLiquidity(address(wbtc), address(dai), 1011393293, 657055640487000000000000, 0, 0, owner, type(uint256).max);
        uniRouter.addLiquidity(address(usdt), address(usdc), 658055640487, 659055640487, 0, 0, owner, type(uint256).max);
        uniRouter.addLiquidity(address(dai), address(usdc), 657055640487000000000000, 658055640487, 0, 0, owner, type(uint256).max);
        uniRouter.addLiquidity(address(dai), address(usdt), 657055640487000000000000, 656055640487, 0, 0, owner, type(uint256).max);

        vm.stopPrank();
    }

    function initSushiswap(address owner) public {
        // Let's do the same thing with `getCode`
        //bytes memory args = abi.encode(arg1, arg2);
        bytes memory factoryArgs = abi.encode(owner);
        bytes memory factoryBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/SushiswapV2Factory.json"), factoryArgs);
        address factoryAddress;
        assembly {
            factoryAddress := create(0, add(factoryBytecode, 0x20), mload(factoryBytecode))
        }

        bytes memory routerArgs = abi.encode(factoryAddress, weth);
        bytes memory routerBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/SushiswapV2Router02.json"), routerArgs);
        address routerAddress;
        assembly {
            routerAddress := create(0, add(routerBytecode, 0x20), mload(routerBytecode))
        }

        sushiFactory = IDeltaSwapFactory(factoryAddress);
        sushiRouter = IDeltaSwapRouter02(routerAddress);

        sushiCfmmHash = hex'e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303'; // UniV2Pair init_code_hash
        sushiCfmmFactory = address(0);


        sushiWethUsdcPool = IDeltaSwapPair(sushiFactory.createPair(address(weth), address(usdc)));
        sushiWethUsdtPool = IDeltaSwapPair(sushiFactory.createPair(address(weth), address(usdt)));
        sushiWethDaiPool = IDeltaSwapPair(sushiFactory.createPair(address(weth), address(dai)));
        sushiWbtcWethPool = IDeltaSwapPair(sushiFactory.createPair(address(wbtc), address(weth)));
        sushiWbtcUsdcPool = IDeltaSwapPair(sushiFactory.createPair(address(wbtc), address(usdc)));
        sushiWbtcUsdtPool = IDeltaSwapPair(sushiFactory.createPair(address(wbtc), address(usdt)));
        sushiWbtcDaiPool = IDeltaSwapPair(sushiFactory.createPair(address(wbtc), address(dai)));
        sushiUsdtUsdcPool = IDeltaSwapPair(sushiFactory.createPair(address(usdt), address(usdc)));
        sushiDaiUsdcPool = IDeltaSwapPair(sushiFactory.createPair(address(dai), address(usdc)));
        sushiDaiUsdtPool = IDeltaSwapPair(sushiFactory.createPair(address(dai), address(usdt)));

        weth.mint(owner, 120);
        usdc.mint(owner, 350_000);
        weth.mint(owner, 890);
        usdt.mint(owner, 2_700_000);
        weth.mint(owner, 120);
        dai.mint(owner, 350_000);
        weth.mint(owner, 220);
        wbtc.mint(owner, 11);
        wbtc.mint(owner, 11);
        usdc.mint(owner, 660_000);
        wbtc.mint(owner, 11);
        usdt.mint(owner, 660_000);
        wbtc.mint(owner, 11);
        dai.mint(owner, 660_000);
        usdc.mint(owner, 660_000);
        usdt.mint(owner, 660_000);
        usdc.mint(owner, 660_000);
        dai.mint(owner, 660_000);
        usdt.mint(owner, 660_000);
        dai.mint(owner, 660_000);

        vm.startPrank(owner);

        weth.approve(address(sushiRouter), type(uint256).max);
        usdc.approve(address(sushiRouter), type(uint256).max);
        usdt.approve(address(sushiRouter), type(uint256).max);
        wbtc.approve(address(sushiRouter), type(uint256).max);
        dai.approve(address(sushiRouter), type(uint256).max);

        sushiRouter.addLiquidity(address(weth), address(usdc), 115594502247137145239, 345648123455, 0, 0, owner, type(uint256).max);
        sushiRouter.addLiquidity(address(weth), address(usdt), 887209737429288199534, 2680657431182, 0, 0, owner, type(uint256).max);
        sushiRouter.addLiquidity(address(weth), address(dai), 115594502247137145239, 345648123455000000000000, 0, 0, owner, type(uint256).max);
        sushiRouter.addLiquidity(address(wbtc), address(weth), 1012393293, 217378372286812000000, 0, 0, owner, type(uint256).max);
        sushiRouter.addLiquidity(address(wbtc), address(usdc), 1012393293, 658055640487, 0, 0, owner, type(uint256).max);
        sushiRouter.addLiquidity(address(wbtc), address(usdt), 1013393293, 659055640487, 0, 0, owner, type(uint256).max);
        sushiRouter.addLiquidity(address(wbtc), address(dai), 1011393293, 657055640487000000000000, 0, 0, owner, type(uint256).max);
        sushiRouter.addLiquidity(address(usdt), address(usdc), 658055640487, 659055640487, 0, 0, owner, type(uint256).max);
        sushiRouter.addLiquidity(address(dai), address(usdc), 657055640487000000000000, 658055640487, 0, 0, owner, type(uint256).max);
        sushiRouter.addLiquidity(address(dai), address(usdt), 657055640487000000000000, 656055640487, 0, 0, owner, type(uint256).max);

        vm.stopPrank();
    }

    function initDeltaSwap(address owner) public {
        // Let's do the same thing with `getCode`
        //bytes memory args = abi.encode(arg1, arg2);

        gsFactory = new GammaPoolFactory(owner);

        bytes memory factoryArgs = abi.encode(owner, owner, address(gsFactory)); // gsFactory
        bytes memory factoryBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/DeltaSwapFactory.json"), factoryArgs);
        address factoryAddress;
        assembly {
            factoryAddress := create(0, add(factoryBytecode, 0x20), mload(factoryBytecode))
        }

        bytes memory routerArgs = abi.encode(factoryAddress, weth);
        bytes memory routerBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/DeltaSwapRouter02.json"), routerArgs);
        address routerAddress;
        assembly {
            routerAddress := create(0, add(routerBytecode, 0x20), mload(routerBytecode))
        }

        dsFactory = IDeltaSwapFactory(factoryAddress);
        dsRouter = IDeltaSwapRouter02(routerAddress);

        vm.prank(owner);
        dsFactory.setGSProtocolId(1);

        dsCfmmHash = hex'a82767a5e39a2e216962a2ebff796dcc37cd05dfd6f7a149e1f8fbb6bf487658'; // DeltaSwapPair init_code_hash
        dsCfmmFactory = address(dsFactory);

        dsWethUsdcPool = IDeltaSwapPair(dsFactory.createPair(address(weth), address(usdc)));
        dsWethUsdtPool = IDeltaSwapPair(dsFactory.createPair(address(weth), address(usdt)));
        dsWethDaiPool = IDeltaSwapPair(dsFactory.createPair(address(weth), address(dai)));
        dsWbtcWethPool = IDeltaSwapPair(dsFactory.createPair(address(wbtc), address(weth)));
        dsWbtcUsdcPool = IDeltaSwapPair(dsFactory.createPair(address(wbtc), address(usdc)));
        dsWbtcUsdtPool = IDeltaSwapPair(dsFactory.createPair(address(wbtc), address(usdt)));
        dsWbtcDaiPool = IDeltaSwapPair(dsFactory.createPair(address(wbtc), address(dai)));
        dsUsdtUsdcPool = IDeltaSwapPair(dsFactory.createPair(address(usdt), address(usdc)));
        dsDaiUsdcPool = IDeltaSwapPair(dsFactory.createPair(address(dai), address(usdc)));
        dsDaiUsdtPool = IDeltaSwapPair(dsFactory.createPair(address(dai), address(usdt)));

        weth.mint(owner, 120);
        usdc.mint(owner, 350_000);
        weth.mint(owner, 890);
        usdt.mint(owner, 2_700_000);
        weth.mint(owner, 120);
        dai.mint(owner, 350_000);
        weth.mint(owner, 220);
        wbtc.mint(owner, 11);
        wbtc.mint(owner, 11);
        usdc.mint(owner, 660_000);
        wbtc.mint(owner, 11);
        usdt.mint(owner, 660_000);
        wbtc.mint(owner, 11);
        dai.mint(owner, 660_000);
        usdc.mint(owner, 660_000);
        usdt.mint(owner, 660_000);
        usdc.mint(owner, 660_000);
        dai.mint(owner, 660_000);
        usdt.mint(owner, 660_000);
        dai.mint(owner, 660_000);

        vm.startPrank(owner);

        dsFactory.setDSFee(2);
        dsFactory.setDSFeeThreshold(0);

        weth.approve(address(dsRouter), type(uint256).max);
        usdc.approve(address(dsRouter), type(uint256).max);
        usdt.approve(address(dsRouter), type(uint256).max);
        wbtc.approve(address(dsRouter), type(uint256).max);
        dai.approve(address(dsRouter), type(uint256).max);

        dsRouter.addLiquidity(address(weth), address(usdc), 115594502247137145239, 345648123455, 0, 0, owner, type(uint256).max);
        dsRouter.addLiquidity(address(weth), address(usdt), 887209737429288199534, 2680657431182, 0, 0, owner, type(uint256).max);
        dsRouter.addLiquidity(address(weth), address(dai), 115594502247137145239, 345648123455000000000000, 0, 0, owner, type(uint256).max);
        dsRouter.addLiquidity(address(wbtc), address(weth), 1012393293, 217378372286812000000, 0, 0, owner, type(uint256).max);
        dsRouter.addLiquidity(address(wbtc), address(usdc), 1012393293, 658055640487, 0, 0, owner, type(uint256).max);
        dsRouter.addLiquidity(address(wbtc), address(usdt), 1013393293, 659055640487, 0, 0, owner, type(uint256).max);
        dsRouter.addLiquidity(address(wbtc), address(dai), 1011393293, 657055640487000000000000, 0, 0, owner, type(uint256).max);
        dsRouter.addLiquidity(address(usdt), address(usdc), 658055640487, 659055640487, 0, 0, owner, type(uint256).max);
        dsRouter.addLiquidity(address(dai), address(usdc), 657055640487000000000000, 658055640487, 0, 0, owner, type(uint256).max);
        dsRouter.addLiquidity(address(dai), address(usdt), 657055640487000000000000, 656055640487, 0, 0, owner, type(uint256).max);

        vm.stopPrank();
    }

    function initAerodrome(address owner) public {
        {
            address poolAddress = createContractFromBytecode("./test/foundry/bytecodes/aerodrome/Pool.json");
            aeroFactory = IAeroPoolFactory(createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome/PoolFactory.json",
                abi.encode(poolAddress)));
            address managedRewardsFactoryAddress = createContractFromBytecode("./test/foundry/bytecodes/aerodrome/ManagedRewardsFactory.json");
            address gaugeFactoryAddress = createContractFromBytecode("./test/foundry/bytecodes/aerodrome/GaugeFactory.json");
            address votingRewardsFactoryAddress = createContractFromBytecode("./test/foundry/bytecodes/aerodrome/VotingRewardsFactory.json");
            address forwarderAddress = createContractFromBytecode("./test/foundry/bytecodes/aerodrome/Forwarder.json");
            address factoryRegistryAddress = createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome/FactoryRegistry.json",
                abi.encode(address(aeroFactory),votingRewardsFactoryAddress,gaugeFactoryAddress,managedRewardsFactoryAddress));
            address aeroAddress = createContractFromBytecode("./test/foundry/bytecodes/aerodrome/Aero.json");
            address votingEscrowAddress = createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome/VotingEscrow.json",
                abi.encode(forwarderAddress,aeroAddress,factoryRegistryAddress));
            aeroVoter = createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome/Voter.json",
                abi.encode(forwarderAddress,votingEscrowAddress,factoryRegistryAddress));
            address rewardsDistributorAddress = createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome/RewardsDistributor.json",
                abi.encode(votingEscrowAddress));
            aeroRouter = IAeroRouter(createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome/Router.json",
                abi.encode(forwarderAddress,factoryRegistryAddress,address(aeroFactory),votingEscrowAddress,aeroVoter,address(weth))));
            address minterAddress = createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome/Minter.json",
                abi.encode(aeroVoter,votingEscrowAddress,rewardsDistributorAddress));

            IAeroToken(aeroAddress).setMinter(minterAddress);
        }

        aeroWethUsdcPool = IAeroPool(aeroFactory.createPool(address(weth), address(usdc), false));
        aeroWethUsdtPool = IAeroPool(aeroFactory.createPool(address(weth), address(usdt), false));
        aeroWethDaiPool = IAeroPool(aeroFactory.createPool(address(weth), address(dai), false));
        aeroWbtcWethPool = IAeroPool(aeroFactory.createPool(address(wbtc), address(weth), false));
        aeroWbtcUsdcPool = IAeroPool(aeroFactory.createPool(address(wbtc), address(usdc), false));
        aeroWbtcUsdtPool = IAeroPool(aeroFactory.createPool(address(wbtc), address(usdt), false));
        aeroWbtcDaiPool = IAeroPool(aeroFactory.createPool(address(wbtc), address(dai), false));
        aeroUsdtUsdcPool = IAeroPool(aeroFactory.createPool(address(usdt), address(usdc), true));
        aeroDaiUsdcPool = IAeroPool(aeroFactory.createPool(address(dai), address(usdc), true));
        aeroDaiUsdtPool = IAeroPool(aeroFactory.createPool(address(dai), address(usdt), true));

        weth.mint(owner, 120);
        usdt.mint(owner, 350_000);
        weth.mint(owner, 890);
        usdc.mint(owner, 2_700_000);
        weth.mint(owner, 120);
        dai.mint(owner, 350_000);
        weth.mint(owner, 220);
        wbtc.mint(owner, 11);
        wbtc.mint(owner, 11);
        usdc.mint(owner, 660_000);
        wbtc.mint(owner, 11);
        usdt.mint(owner, 660_000);
        wbtc.mint(owner, 11);
        dai.mint(owner, 660_000);
        usdc.mint(owner, 660_000);
        usdt.mint(owner, 660_000);
        usdc.mint(owner, 660_000);
        dai.mint(owner, 660_000);
        usdt.mint(owner, 660_000);
        dai.mint(owner, 660_000);

        vm.startPrank(owner);

        weth.approve(address(aeroRouter), type(uint256).max);
        usdc.approve(address(aeroRouter), type(uint256).max);
        usdt.approve(address(aeroRouter), type(uint256).max);
        dai.approve(address(aeroRouter), type(uint256).max);
        wbtc.approve(address(aeroRouter), type(uint256).max);

        aeroRouter.addLiquidity(address(weth), address(dai), false, 115594502247137145239, 345648123455000000000000, 0, 0, owner, type(uint256).max);
        aeroRouter.addLiquidity(address(wbtc), address(weth), false, 1012393293, 217378372286812000000, 0, 0, owner, type(uint256).max);
        aeroRouter.addLiquidity(address(wbtc), address(usdc), false, 1012393293, 658055640487, 0, 0, owner, type(uint256).max);
        aeroRouter.addLiquidity(address(wbtc), address(usdt), false, 1013393293, 659055640487, 0, 0, owner, type(uint256).max);
        aeroRouter.addLiquidity(address(wbtc), address(dai), false, 1011393293, 657055640487000000000000, 0, 0, owner, type(uint256).max);
        aeroRouter.addLiquidity(address(dai), address(usdt), true, 656055640487000000000000, 656055640487, 0, 0, owner, type(uint256).max);
        aeroRouter.addLiquidity(address(usdc), address(weth), false, 2680657431182, 887209737429288199534, 0, 0, owner, type(uint256).max);
        aeroRouter.addLiquidity(address(usdt), address(weth), false, 345648123455, 115594502247137145239, 0, 0, owner, type(uint256).max);
        aeroRouter.addLiquidity(address(usdt), address(usdc), true, 245648123455, 245648123455, 0, 0, owner, type(uint256).max);
        aeroRouter.addLiquidity(address(usdc), address(dai), true, 245648123455, 245648123455000000000000, 0, 0, owner, type(uint256).max);

        vm.stopPrank();
    }

    function initAerodromeCL(address owner, address _voter) public {
        address clPoolAddress = createContractFromBytecode("./test/foundry/bytecodes/aerodrome-cl/CLPool.json");

        aeroCLFactory = IAeroCLPoolFactory(createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome-cl/CLFactory.json",
            abi.encode(_voter,clPoolAddress)));

        // deploy gauges
        address clGaugeAddress = createContractFromBytecode("./test/foundry/bytecodes/aerodrome-cl/CLGauge.json");
        address clGaugeFactoryAddress = createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome-cl/CLGaugeFactory.json",
            abi.encode(_voter, clGaugeAddress));

        address nftPositionDescriptorAddress = createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome-cl/NonfungibleTokenPositionDescriptor.json",
            abi.encode(address(weth), bytes32("ETH")));

        address nonfungiblePositionManager = createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome-cl/NonfungiblePositionManager.json",
            abi.encode(address(aeroCLFactory), address(weth), nftPositionDescriptorAddress, "Slipstream Position NFT v1", "AERO-CL-POS"));
        // set nft manager in the factories
        ICLGaugeFactory(clGaugeFactoryAddress).setNonfungiblePositionManager(nonfungiblePositionManager);
        ICLGaugeFactory(clGaugeFactoryAddress).setNotifyAdmin(owner);

        address swapFeeModuleAddress = createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome-cl/CustomSwapFeeModule.json",
            abi.encode(address(aeroCLFactory)));
        address unstakedFeeModuleAddress = createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome-cl/CustomUnstakedFeeModule.json",
            abi.encode(address(aeroCLFactory)));

        aeroCLFactory.setSwapFeeModule(swapFeeModuleAddress);
        aeroCLFactory.setUnstakedFeeModule(unstakedFeeModuleAddress);

        // transfer permissions
        IAeroCLPositionManager(nonfungiblePositionManager).setOwner(owner);
        aeroCLFactory.setOwner(owner);
        aeroCLFactory.setSwapFeeManager(owner);
        aeroCLFactory.setUnstakedFeeManager(owner);

        address mixedQuoterAddress = createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome-cl/MixedRouteQuoterV1.json",
            abi.encode(address(aeroCLFactory),address(aeroFactory),address(weth)));

        aeroCLQuoter = createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome-cl/QuoterV2.json",
            abi.encode(address(aeroCLFactory),address(weth)));

        address swapRouterAddress = createContractFromBytecodeWithArgs("./test/foundry/bytecodes/aerodrome-cl/SwapRouter.json",
            abi.encode(address(aeroCLFactory),address(weth)));

        aeroCLWethUsdcPool = IAeroCLPool(aeroCLFactory.createPool(address(weth), address(usdc), aeroCLTickSpacing, wethUsdcSqrtPriceX96));
        aeroCLWethUsdtPool = IAeroCLPool(aeroCLFactory.createPool(address(weth), address(usdt), aeroCLTickSpacing, wethUsdcSqrtPriceX96));
        aeroCLWethDaiPool = IAeroCLPool(aeroCLFactory.createPool(address(weth), address(dai), aeroCLTickSpacing, wethDaiSqrtPriceX96));
        aeroCLWbtcWethPool = IAeroCLPool(aeroCLFactory.createPool(address(wbtc), address(weth), aeroCLTickSpacing, wbtcWethSqrtPriceX96));
        aeroCLWbtcUsdcPool = IAeroCLPool(aeroCLFactory.createPool(address(wbtc), address(usdc), aeroCLTickSpacing, wbtcUsdcSqrtPriceX96));
        aeroCLWbtcUsdtPool = IAeroCLPool(aeroCLFactory.createPool(address(wbtc), address(usdt), aeroCLTickSpacing, wbtcUsdcSqrtPriceX96));
        aeroCLWbtcDaiPool = IAeroCLPool(aeroCLFactory.createPool(address(wbtc), address(dai), aeroCLTickSpacing, wbtcDaiSqrtPriceX96));
        aeroCLUsdtUsdcPool = IAeroCLPool(aeroCLFactory.createPool(address(usdt), address(usdc), aeroCLTickSpacing, usdtUsdcSqrtPriceX96));
        aeroCLDaiUsdcPool = IAeroCLPool(aeroCLFactory.createPool(address(dai), address(usdc), aeroCLTickSpacing, daiUsdcSqrtPriceX96));
        aeroCLDaiUsdtPool = IAeroCLPool(aeroCLFactory.createPool(address(dai), address(usdt), aeroCLTickSpacing, daiUsdcSqrtPriceX96));

        weth.mint(owner, 120);
        usdc.mint(owner, 350_000);
        weth.mint(owner, 890);
        usdt.mint(owner, 2_700_000);
        weth.mint(owner, 120);
        dai.mint(owner, 350_000);
        weth.mint(owner, 220);
        wbtc.mint(owner, 11);
        wbtc.mint(owner, 11);
        usdc.mint(owner, 660_000);
        wbtc.mint(owner, 11);
        usdt.mint(owner, 660_000);
        wbtc.mint(owner, 11);
        dai.mint(owner, 660_000);
        usdc.mint(owner, 660_000);
        usdt.mint(owner, 660_000);
        usdc.mint(owner, 660_000);
        dai.mint(owner, 660_000);
        usdt.mint(owner, 660_000);
        dai.mint(owner, 660_000);

        vm.startPrank(owner);

        weth.approve(nonfungiblePositionManager, type(uint256).max);
        usdc.approve(nonfungiblePositionManager, type(uint256).max);
        usdt.approve(nonfungiblePositionManager, type(uint256).max);
        wbtc.approve(nonfungiblePositionManager, type(uint256).max);
        dai.approve(nonfungiblePositionManager, type(uint256).max);

        addLiquidityAeroCL(nonfungiblePositionManager, address(weth), address(usdc), aeroCLTickSpacing, 115594502247137145239, 345648123455);
        addLiquidityAeroCL(nonfungiblePositionManager, address(weth), address(usdt), aeroCLTickSpacing, 887209737429288199534, 2680657431182);
        addLiquidityAeroCL(nonfungiblePositionManager, address(weth), address(dai), aeroCLTickSpacing, 115594502247137145239, 345648123455000000000000);
        addLiquidityAeroCL(nonfungiblePositionManager, address(wbtc), address(weth), aeroCLTickSpacing, 1012393293, 217378372286812000000);
        addLiquidityAeroCL(nonfungiblePositionManager, address(wbtc), address(usdc), aeroCLTickSpacing, 1012393293, 658055640487);
        addLiquidityAeroCL(nonfungiblePositionManager, address(wbtc), address(usdt), aeroCLTickSpacing, 1013393293, 659055640487);
        addLiquidityAeroCL(nonfungiblePositionManager, address(wbtc), address(dai), aeroCLTickSpacing, 1011393293, 657055640487000000000000);
        addLiquidityAeroCL(nonfungiblePositionManager, address(usdt), address(usdc), aeroCLTickSpacing, 658055640487, 659055640487);
        addLiquidityAeroCL(nonfungiblePositionManager, address(dai), address(usdc), aeroCLTickSpacing, 657055640487000000000000, 658055640487);
        addLiquidityAeroCL(nonfungiblePositionManager, address(dai), address(usdt), aeroCLTickSpacing, 657055640487000000000000, 656055640487);

        vm.stopPrank();
    }

    function addLiquidity(address token0, address token1, uint256 amount0, uint256 amount1, address to) public returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB, liquidity) = uniRouter.addLiquidity(token0, token1, amount0, amount1, 0, 0, to, type(uint256).max);
    }

    function createContractFromBytecode(string memory bytecodePath) internal virtual returns(address addr) {
        bytes memory bytecode = abi.encodePacked(vm.getCode(bytecodePath));
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }

    function createContractFromBytecodeWithArgs(string memory bytecodePath, bytes memory args) internal virtual returns(address addr) {
        bytes memory bytecode = abi.encodePacked(vm.getCode(bytecodePath), args);
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }

    function addLiquidityV3(address nftPositionManager, address token0, address token1, uint24 poolFee, uint256 amount0, uint256 amount1) internal {
        IPositionManagerMintable.MintParams memory mintParams = IPositionManagerMintable.MintParams({
            token0: token0,
            token1: token1,
            fee: poolFee,
            tickLower: -887200,
            tickUpper: 887200,
            // tickLower: -216200,
            // tickUpper: -176200,
            amount0Desired: amount0,  // 115.5 WETH
            amount1Desired: amount1,   // 345648 USDC
            amount0Min: 0,
            amount1Min: 0,
            recipient: msg.sender,
            deadline: type(uint256).max
        });
        IPositionManagerMintable(nftPositionManager).mint(mintParams);
    }

    function addLiquidityAeroCL(address nftPositionManager, address token0, address token1, int24 tickSpacing, uint256 amount0, uint256 amount1) internal {
        IAeroPositionManagerMintable.MintParams memory mintParams = IAeroPositionManagerMintable.MintParams({
            token0: token0,
            token1: token1,
            tickSpacing: tickSpacing,
            tickLower: -887200,
            tickUpper: 887200,
            amount0Desired: amount0,  // 115.5 WETH
            amount1Desired: amount1,   // 345648 USDC
            amount0Min: 0,
            amount1Min: 0,
            recipient: msg.sender,
            deadline: type(uint256).max,
            sqrtPriceX96: 0
        });
        IAeroPositionManagerMintable(nftPositionManager).mint(mintParams);
    }
}