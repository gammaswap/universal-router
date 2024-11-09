// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '../../routes/DeltaSwap.sol';

contract TestDeltaSwap is DeltaSwap {

    constructor(uint16 _protocolId, address _factory, address _WETH) DeltaSwap(_protocolId, _factory, _WETH) {
    }

    function getInitCodeHash() public virtual view returns(bytes32) {
        return initCodeHash();
    }

    function getPairFor(address tokenA, address tokenB) public virtual view
        returns(address pair, address token0, address token1) {
        return pairFor(tokenA, tokenB, 0);
    }

    function getPairReserves(address tokenA, address tokenB) public virtual view
        returns(uint256 reserveA, uint256 reserveB, address pair) {
        return getReserves(tokenA, tokenB);
    }
}
