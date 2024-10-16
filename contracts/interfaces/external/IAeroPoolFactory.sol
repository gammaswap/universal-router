pragma solidity ^0.8.0;

interface IAeroPoolFactory {

    /// @notice Returns fee for a pool, as custom fees are possible.
    function getFee(address _pool, bool _stable) external view returns (uint256);

    function createPool(address tokenA, address tokenB, bool stable) external returns (address pool);
}
