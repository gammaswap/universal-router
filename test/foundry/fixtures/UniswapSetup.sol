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

import "../../../contracts/interfaces/IPositionManagerMintable.sol";
import "./TokensSetup.sol";

contract UniswapSetup is TokensSetup {

    IDeltaSwapFactory public uniFactory;
    IDeltaSwapRouter02 public uniRouter;
    IDeltaSwapPair public uniPair;
    IDeltaSwapPair public wethUsdcPool;
    IDeltaSwapPair public wethUsdtPool;

    bytes32 public cfmmHash;
    address public cfmmFactory;

    IUniswapV3Factory public uniFactoryV3;
    IUniswapV3Pool public wethUsdcPoolV3;
    IUniswapV3Pool public wethUsdtPoolV3;
    IQuoterV2 public quoter;

    uint24 public immutable poolFee1 = 10000;    // fee 1%
    uint24 public immutable poolFee2 = 500;    // fee 0.05%
    uint160 public immutable sqrtPriceX96 = 4339505179874779489431521;  // 1 WETH = 3000 USDC

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

    function addLiquidity(address token0, address token1, uint256 amount0, uint256 amount1, address to) public returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB, liquidity) = uniRouter.addLiquidity(token0, token1, amount0, amount1, 0, 0, to, type(uint256).max);
    }

    function initDeltaSwap(address owner) public {
        // Let's do the same thing with `getCode`
        //bytes memory args = abi.encode(arg1, arg2);
        bytes memory factoryArgs = abi.encode(owner, owner, vm.addr(0x6666666666)); // gsFactory
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

        uniFactory = IDeltaSwapFactory(factoryAddress);
        uniRouter = IDeltaSwapRouter02(routerAddress);
        uniFactory.setGSProtocolId(1);

        cfmmHash = hex'a82767a5e39a2e216962a2ebff796dcc37cd05dfd6f7a149e1f8fbb6bf487658'; // DeltaSwapPair init_code_hash
        cfmmFactory = address(uniFactory);
    }
}