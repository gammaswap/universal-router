// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import './UniswapV2.sol';

/// @title Sushiswap Protocol Route contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Route contract to implement swaps in Sushiswap AMMs
/// @dev Implements IProtocolRoute functions to quote and handle one AMM swap at a time
contract SushiswapV2 is UniswapV2 {

    /// @dev Initialize `_protocolId`, `_factory`, and `WETH` address
    constructor(uint16 _protocolId, address _factory, address _WETH) UniswapV2(_protocolId, _factory, _WETH) {
    }

    /// @dev init code hash of Sushiswap pools. Used to calculate pool address without external calls
    function initCodeHash() internal override pure returns(bytes32) {
        return 0xe18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303;
    }
}
