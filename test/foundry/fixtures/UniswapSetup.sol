// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IPoolInitializer.sol";
import "@uniswap/swap-router-contracts/contracts/interfaces/IQuoterV2.sol";

import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapFactory.sol";
import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapPair.sol";
import "@gammaswap/v1-deltaswap/contracts/interfaces/IDeltaSwapRouter02.sol";
import "@gammaswap/v1-core/contracts/GammaPoolFactory.sol";

import "../../../contracts/interfaces/external/IAeroPoolFactory.sol";
import "../../../contracts/interfaces/external/IAeroPool.sol";
import "../../../contracts/test/IAeroRouter.sol";
import "../../../contracts/test/IAeroToken.sol";
import "../../../contracts/test/IPositionManagerMintable.sol";
import "./TokensSetup.sol";

contract UniswapSetup is TokensSetup {

    IDeltaSwapFactory public uniFactory;
    IDeltaSwapRouter02 public uniRouter;
    IDeltaSwapPair public uniPair;
    IDeltaSwapPair public wethUsdcPool;
    IDeltaSwapPair public wethUsdtPool;

    bytes32 public cfmmHash;
    address public cfmmFactory;

    IDeltaSwapFactory public sushiFactory;
    IDeltaSwapRouter02 public sushiRouter;
    IDeltaSwapPair public sushiWethUsdcPool;
    IDeltaSwapPair public sushiWethUsdtPool;

    bytes32 public sushiCfmmHash; // DeltaSwapPair init_code_hash
    address public sushiCfmmFactory;

    GammaPoolFactory public gsFactory;
    IDeltaSwapFactory public dsFactory;
    IDeltaSwapRouter02 public dsRouter;
    IDeltaSwapPair public dsWethUsdcPool;
    IDeltaSwapPair public dsWethUsdtPool;

    bytes32 public dsCfmmHash; // DeltaSwapPair init_code_hash
    address public dsCfmmFactory;

    IUniswapV3Factory public uniFactoryV3;
    IUniswapV3Pool public wethUsdcPoolV3;
    IUniswapV3Pool public wethUsdtPoolV3;
    IQuoterV2 public quoter;

    uint24 public immutable poolFee1 = 10000;    // fee 1%
    uint24 public immutable poolFee2 = 500;    // fee 0.05%
    uint160 public immutable sqrtPriceX96 = 4339505179874779489431521;  // 1 WETH = 3000 USDC

    IAeroPoolFactory public aeroFactory;
    IAeroRouter public aeroRouter;

    IAeroPool public aeroWethUsdcPool;
    IAeroPool public aeroWethUsdtPool;
    IAeroPool public aeroUsdcUsdtPool;

    function addLiquidity(address token0, address token1, uint256 amount0, uint256 amount1, address to) public returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB, liquidity) = uniRouter.addLiquidity(token0, token1, amount0, amount1, 0, 0, to, type(uint256).max);
    }

    function initUniswapV3(address owner) public {
        bytes memory factoryBytecode = abi.encodePacked(vm.getCode("./node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json"));
        assembly {
            sstore(uniFactoryV3.slot, create(0, add(factoryBytecode, 0x20), mload(factoryBytecode)))
        }
        // uniFactoryV3.enableFeeAmount(100, 1);

        bytes memory tickLensBytecode = abi.encodePacked(vm.getCode("./node_modules/@uniswap/v3-periphery/artifacts/contracts/lens/TickLens.sol/TickLens.json"));
        address tickLens;
        assembly {
            tickLens := create(0, add(tickLensBytecode, 0x20), mload(tickLensBytecode))
        }

        bytes memory nftDescriptorLibBytecode = abi.encodePacked(vm.getCode("./node_modules/@uniswap/v3-periphery/artifacts/contracts/libraries/NFTDescriptor.sol/NFTDescriptor.json"));
        address nftDescriptorLib;
        assembly {
            nftDescriptorLib := create(0, add(nftDescriptorLibBytecode, 0x20), mload(nftDescriptorLibBytecode))
        }

        bytes memory nftPositionManagerBytecode = abi.encodePacked(vm.getCode("./node_modules/@uniswap/v3-periphery/artifacts/contracts/NonfungiblePositionManager.sol/NonfungiblePositionManager.json"), abi.encode(address(uniFactoryV3), address(weth), address(0)));
        address nftPositionManager;
        assembly {
            nftPositionManager := create(0, add(nftPositionManagerBytecode, 0x20), mload(nftPositionManagerBytecode))
        }

        bytes memory quoterBytecode = abi.encodePacked(vm.getCode("./node_modules/@uniswap/swap-router-contracts/artifacts/contracts/lens/QuoterV2.sol/QuoterV2.json"), abi.encode(address(uniFactoryV3), address(weth)));
        assembly {
            sstore(quoter.slot, create(0, add(quoterBytecode, 0x20), mload(quoterBytecode)))
        }

        // Deploy Weth/Usdc pool
        wethUsdcPoolV3 = IUniswapV3Pool(
            IPoolInitializer(nftPositionManager).createAndInitializePoolIfNecessary(address(weth), address(usdc), poolFee1, sqrtPriceX96)
        );

        // Deploy Weth/Usdt pool
        wethUsdtPoolV3 = IUniswapV3Pool(
            IPoolInitializer(nftPositionManager).createAndInitializePoolIfNecessary(address(weth), address(usdt), poolFee2, sqrtPriceX96)
        );

        weth.mint(owner, 120);
        usdc.mint(owner, 350_000);
        weth.mint(owner, 890);
        usdt.mint(owner, 2_700_000);

        vm.startPrank(owner);

        weth.approve(nftPositionManager, type(uint256).max);
        usdc.approve(nftPositionManager, type(uint256).max);
        usdt.approve(nftPositionManager, type(uint256).max);

        // Add liquidity to WETH-USDC pool
        IPositionManagerMintable.MintParams memory mintParams = IPositionManagerMintable.MintParams({
            token0: address(weth),
            token1: address(usdc),
            fee: poolFee1,
            tickLower: -887200,
            tickUpper: 887200,
            // tickLower: -216200,
            // tickUpper: -176200,
            amount0Desired: 115594502247137145239,  // 115.5 WETH
            amount1Desired: 345648123455,   // 345648 USDC
            amount0Min: 0,
            amount1Min: 0,
            recipient: msg.sender,
            deadline: type(uint256).max
        });
        IPositionManagerMintable(nftPositionManager).mint(mintParams);

        // Add liquidity to WETH-USDT pool
        mintParams = IPositionManagerMintable.MintParams({
            token0: address(weth),
            token1: address(usdt),
            fee: poolFee2,
            tickLower: -887200,
            tickUpper: 887200,
            amount0Desired: 887209737429288199534,  // 887.2 WETH
            amount1Desired: 2680657431182,   // 2680657 USDT
            amount0Min: 0,
            amount1Min: 0,
            recipient: msg.sender,
            deadline: type(uint256).max
        });
        IPositionManagerMintable(nftPositionManager).mint(mintParams);

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

        weth.mint(owner, 120);
        usdt.mint(owner, 350_000);
        weth.mint(owner, 890);
        usdc.mint(owner, 2_700_000);

        vm.startPrank(owner);

        weth.approve(address(uniRouter), type(uint256).max);
        usdc.approve(address(uniRouter), type(uint256).max);
        usdt.approve(address(uniRouter), type(uint256).max);

        uniRouter.addLiquidity(address(usdc), address(weth), 2680657431182, 887209737429288199534, 0, 0, owner, type(uint256).max);
        uniRouter.addLiquidity(address(usdt), address(weth), 345648123455, 115594502247137145239, 0, 0, owner, type(uint256).max);

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

        weth.mint(owner, 120);
        usdt.mint(owner, 350_000);
        weth.mint(owner, 890);
        usdc.mint(owner, 2_700_000);

        vm.startPrank(owner);

        weth.approve(address(sushiRouter), type(uint256).max);
        usdc.approve(address(sushiRouter), type(uint256).max);
        usdt.approve(address(sushiRouter), type(uint256).max);

        sushiRouter.addLiquidity(address(usdc), address(weth), 2680657431182, 887209737429288199534, 0, 0, owner, type(uint256).max);
        sushiRouter.addLiquidity(address(usdt), address(weth), 345648123455, 115594502247137145239, 0, 0, owner, type(uint256).max);
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

        weth.mint(owner, 120);
        usdt.mint(owner, 350_000);
        weth.mint(owner, 890);
        usdc.mint(owner, 2_700_000);

        vm.startPrank(owner);

        dsFactory.setDSFee(2);
        dsFactory.setDSFeeThreshold(0);

        weth.approve(address(dsRouter), type(uint256).max);
        usdc.approve(address(dsRouter), type(uint256).max);
        usdt.approve(address(dsRouter), type(uint256).max);

        dsRouter.addLiquidity(address(usdc), address(weth), 2680657431182, 887209737429288199534, 0, 0, owner, type(uint256).max);
        dsRouter.addLiquidity(address(usdt), address(weth), 345648123455, 115594502247137145239, 0, 0, owner, type(uint256).max);

        vm.stopPrank();
    }

    function createContractFromBytecode(string memory bytecodePath) internal virtual returns(address addr) {
        bytes memory bytecode = abi.encodePacked(vm.getCode(bytecodePath));
        assembly {
            addr := create(0, add(bytecode, 0x20), mload(bytecode))
        }
    }

    function initAerodrome(address owner) public {
        // Let's do the same thing with `getCode`
        {
            address poolAddress = createContractFromBytecode("./test/foundry/bytecodes/aerodrome/Pool.json");
            {
                address factoryAddress;
                bytes memory factoryBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/aerodrome/PoolFactory.json"), abi.encode(poolAddress));
                assembly {
                    factoryAddress := create(0, add(factoryBytecode, 0x20), mload(factoryBytecode))
                }
                aeroFactory = IAeroPoolFactory(factoryAddress);
            }
            address managedRewardsFactoryAddress = createContractFromBytecode("./test/foundry/bytecodes/aerodrome/ManagedRewardsFactory.json");
            address gaugeFactoryAddress = createContractFromBytecode("./test/foundry/bytecodes/aerodrome/GaugeFactory.json");
            address votingRewardsFactoryAddress = createContractFromBytecode("./test/foundry/bytecodes/aerodrome/VotingRewardsFactory.json");
            address forwarderAddress = createContractFromBytecode("./test/foundry/bytecodes/aerodrome/Forwarder.json");
            address factoryRegistryAddress;
            {
                bytes memory factoryRegistryBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/aerodrome/FactoryRegistry.json"),
                    abi.encode(address(aeroFactory),votingRewardsFactoryAddress,gaugeFactoryAddress,managedRewardsFactoryAddress));
                assembly {
                    factoryRegistryAddress := create(0, add(factoryRegistryBytecode, 0x20), mload(factoryRegistryBytecode))
                }
            }
            address aeroAddress = createContractFromBytecode("./test/foundry/bytecodes/aerodrome/Aero.json");
            address votingEscrowAddress;
            {
                bytes memory votingEscrowBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/aerodrome/VotingEscrow.json"),
                    abi.encode(forwarderAddress,aeroAddress,factoryRegistryAddress));
                assembly {
                    votingEscrowAddress := create(0, add(votingEscrowBytecode, 0x20), mload(votingEscrowBytecode))
                }
            }
            address voterAddress;
            {
                bytes memory voterBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/aerodrome/Voter.json"),
                    abi.encode(forwarderAddress,votingEscrowAddress,factoryRegistryAddress));
                assembly {
                    voterAddress := create(0, add(voterBytecode, 0x20), mload(voterBytecode))
                }
            }

            address rewardsDistributorAddress;
            {
                bytes memory rewardsDistributorBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/aerodrome/RewardsDistributor.json"),
                    abi.encode(votingEscrowAddress));
                assembly {
                    rewardsDistributorAddress := create(0, add(rewardsDistributorBytecode, 0x20), mload(rewardsDistributorBytecode))
                }
            }

            {
                address routerAddress;
                bytes memory routerBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/aerodrome/Router.json"),
                    abi.encode(forwarderAddress,factoryRegistryAddress,address(aeroFactory),votingEscrowAddress,voterAddress,address(weth)));
                assembly {
                    routerAddress := create(0, add(routerBytecode, 0x20), mload(routerBytecode))
                }
                aeroRouter = IAeroRouter(routerAddress);
            }

            address minterAddress;
            {
                bytes memory minterBytecode = abi.encodePacked(vm.getCode("./test/foundry/bytecodes/aerodrome/Minter.json"),
                    abi.encode(voterAddress,votingEscrowAddress,rewardsDistributorAddress));
                assembly {
                    minterAddress := create(0, add(minterBytecode, 0x20), mload(minterBytecode))
                }
            }

            IAeroToken(aeroAddress).setMinter(minterAddress);
        }

        aeroWethUsdcPool = IAeroPool(aeroFactory.createPool(address(weth), address(usdc), false));
        aeroWethUsdtPool = IAeroPool(aeroFactory.createPool(address(weth), address(usdt), false));
        aeroUsdcUsdtPool = IAeroPool(aeroFactory.createPool(address(usdc), address(usdt), true));

        weth.mint(owner, 120);
        usdt.mint(owner, 350_000);
        weth.mint(owner, 890);
        usdc.mint(owner, 2_700_000);

        usdt.mint(owner, 250_000);
        usdc.mint(owner, 250_000);

        vm.startPrank(owner);

        weth.approve(address(aeroRouter), type(uint256).max);
        usdc.approve(address(aeroRouter), type(uint256).max);
        usdt.approve(address(aeroRouter), type(uint256).max);

        aeroRouter.addLiquidity(address(usdc), address(weth), false, 2680657431182, 887209737429288199534, 0, 0, owner, type(uint256).max);
        aeroRouter.addLiquidity(address(usdt), address(weth), false, 345648123455, 115594502247137145239, 0, 0, owner, type(uint256).max);
        aeroRouter.addLiquidity(address(usdt), address(usdc), true, 245648123455, 245648123455, 0, 0, owner, type(uint256).max);

        vm.stopPrank();
    }
}