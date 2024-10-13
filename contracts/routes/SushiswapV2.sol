pragma solidity ^0.8.0;

import "./UniswapV2.sol";

contract SushiswapV2 is UniswapV2 {

    constructor(uint16 _protocolId, address _factory) UniswapV2(_protocolId, _factory) {
    }

    function initCodeHash() internal override pure returns(bytes32) {
        return 0xe18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303;
    }
}
