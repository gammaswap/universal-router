// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../routes/UniswapV2.sol";

contract TestUniswapV2 is UniswapV2 {

    constructor(uint16 _protocolId, address _factory, address _WETH) UniswapV2(_protocolId, _factory, _WETH) {
    }

    function getInitCodeHash() public virtual view returns(bytes32) {
        return initCodeHash();
    }

    function getPairFor(address tokenA, address tokenB) public virtual view
        returns(address pair, address token0, address token1) {
        return pairFor(tokenA, tokenB);
    }

    function getPairReserves(address tokenA, address tokenB) public virtual view
        returns(uint256 reserveA, uint256 reserveB, address pair) {
        return getReserves(tokenA, tokenB);
    }
}
