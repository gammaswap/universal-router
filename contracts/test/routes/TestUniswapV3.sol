// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import '../../routes/UniswapV3.sol';

contract TestUniswapV3 is UniswapV3 {

    constructor(uint16 _protocolId, address _factory, address _WETH)
        UniswapV3(_protocolId, _factory, _WETH) {
    }

    function getInitCodeHash() public virtual view returns(bytes32) {
        return POOL_INIT_CODE_HASH;
    }

    function getPairFor(address tokenA, address tokenB, uint24 fee) public virtual view
        returns(address pair) {
        return pairFor(tokenA, tokenB, fee);
    }

    function getDecodedPrice(uint256 sqrtPriceX96, uint256 decimals) public virtual view
        returns(uint256 price) {
        return decodePrice(sqrtPriceX96, decimals);
    }
}
