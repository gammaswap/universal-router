// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import './UniswapV2.sol';

/// @title SushiswapV2 Protocol Route contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Route contract to implement swaps in Sushiswap AMMs
/// @dev Implements IProtocolRoute functions to quote and handle one AMM swap at a time
contract SushiswapV2 is UniswapV2 {

    /// @dev init code hash used to calculate pair addresses
    bytes32 public immutable INIT_CODE_HASH;

    /// @dev Initialize `_protocolId`, `_factory`, and `WETH` address
    constructor(uint16 _protocolId, address _factory, address _WETH, bytes32 initCodeHash) UniswapV2(_protocolId, _factory, _WETH) {
        INIT_CODE_HASH = initCodeHash;
    }

    /// @dev init code hash of Sushiswap pools. Used to calculate pool address without external calls
    function initCodeHash() internal override virtual view returns(bytes32) {
        return INIT_CODE_HASH;
    }
}
