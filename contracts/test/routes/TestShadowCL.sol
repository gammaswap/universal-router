// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '../../routes/ShadowCL.sol';

contract TestShadowCL is ShadowCL {
    constructor(uint16 _protocolId, address _factory, address _WETH)
        ShadowCL(_protocolId, _factory, _WETH) {}

    function getPairFor(address tokenA, address tokenB, int24 tickSpacing) public view returns (address pair) {
        (pair,,) = pairFor(tokenA, tokenB, uint24(tickSpacing));
    }

    function getDecodedPrice(uint256 sqrtPriceX96, uint256 decimals) public pure returns (uint256 price) {
        return decodePrice(sqrtPriceX96, decimals);
    }
}
