// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import './SushiswapV2.sol';

/// @title Sushiswap Protocol Route Test contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Route contract to implement swaps in Sushiswap AMMs
/// @dev Implements IProtocolRoute functions to quote and handle one AMM swap at a time
contract SushiswapV2Test is SushiswapV2 {

    /// @dev Initialize `_protocolId`, `_factory`, and `WETH` address
    constructor(uint16 _protocolId, address _factory, address _WETH) SushiswapV2(_protocolId, _factory, _WETH) {
    }

    /// @dev init code hash of Sushiswap pools. Used to calculate pool address without external calls
    function initCodeHash() internal override virtual pure returns(bytes32) {
        return 0xef6ec070bf409122f2104229fda397355457c9f7dec81971f5cccd2e45cb1eb4;
    }
}
