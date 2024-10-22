// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '../../routes/AerodromeCL.sol';

contract TestAerodromeCL is AerodromeCL {

    constructor(uint16 _protocolId, address _factory, address _WETH)
        AerodromeCL(_protocolId, _factory, _WETH) {
    }

    function getPairFor(address tokenA, address tokenB, int24 tickSpacing) public virtual view
        returns(address pair) {
        return pairFor(tokenA, tokenB, tickSpacing);
    }

    function getDecodedPrice(uint256 sqrtPriceX96, uint256 decimals) public virtual view
        returns(uint256 price) {
        return decodePrice(sqrtPriceX96, decimals);
    }
}
