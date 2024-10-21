// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "../../routes/Aerodrome.sol";

contract TestAerodrome is Aerodrome {

    constructor(uint16 _protocolId, address _factory, bool _isStable, address _WETH)
        Aerodrome(_protocolId, _factory, _isStable, _WETH) {
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
