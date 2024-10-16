// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "./fixtures/TestBed.sol";
import "./utils/Random.sol";
import "../../contracts/routes/UniswapV2.sol";

contract UniversalRouterTest is TestBed {

    address owner;
    UniswapV2 uniV2Route;
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

        // set up routes
        router.addProtocol(address(uniV2Route));
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

        UniswapV2 route2 = new UniswapV2(2, address(uniFactory), address(weth));

        assertEq(router.protocols(2),address(0));

        assertEq(router.owner(), address(this));

        address userX = vm.addr(12345);
        vm.prank(userX);
        vm.expectRevert("Ownable: caller is not the owner");
        router.addProtocol(address(route2));

        router.addProtocol(address(route2));
        assertEq(router.protocols(2),address(route2));

        UniswapV2 route2a = new UniswapV2(2, address(uniFactory), address(weth));
        vm.expectRevert("PROTOCOL_ID_USED");
        router.addProtocol(address(route2a));

        vm.prank(userX);
        vm.expectRevert("Ownable: caller is not the owner");
        router.removeProtocol(0);

        vm.expectRevert("INVALID_PROTOCOL_ID");
        router.removeProtocol(0);

        vm.expectRevert("PROTOCOL_ID_UNUSED");
        router.removeProtocol(3);

        router.removeProtocol(2);
        assertEq(router.protocols(2),address(0));
    }

    function testCalcRoutes(uint8 tokenChoices, uint128 seed) public {
        bytes memory path = createPath(tokenChoices, seed);
    }

    function createPath(uint8 tokenChoices, uint128 seed) internal view returns(bytes memory) {
        address[] memory _tokens = tokens;
        _tokens = random.shuffleAddresses(_tokens, seed);
        _tokens = getTokens(tokenChoices, _tokens);

        bytes memory _path = abi.encodePacked(_tokens[0]);

        for(uint256 i = 1; i < _tokens.length; i++) {
            uint16 protocolId = uint16(random.getRandomNumber(PROTOCOL_ROUTES_COUNT + 1, seed + i + 10));
            uint24 fee = protocolId == 6 ? poolFee1 : 0;
            _path = abi.encodePacked(_path, protocolId, fee, _tokens[i]);
        }
        return _path;
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
        console.logBytes(val);
        router.getAmountsOut(1e18, val);

        /*uint256 sqrtPriceX96 = 3984769773545821863947016;
        uint256 sqrtPrice = sqrtPriceX96 * sqrtPriceX96 * (10**18);// * (10**6);
        console.log("sqrtPrice");
        console.log(sqrtPrice);
        console.log("(2**192)");
        uint256 num = 2**192;
        console.log(num);
        uint256 price = sqrtPrice / (2**192);
        console.log("price");
        console.log(price);/**/
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
