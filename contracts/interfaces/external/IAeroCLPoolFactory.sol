// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface IAeroCLPoolFactory {
    function poolImplementation() external view returns(address);
    function setOwner(address _owner) external;
    function setSwapFeeModule(address _swapFeeModule) external;
    function setUnstakedFeeModule(address _unstakedFeeModule) external;
    function setSwapFeeManager(address _swapFeeManager) external;
    function setUnstakedFeeManager(address _unstakedFeeManager) external;
    function createPool(address tokenA, address tokenB, int24 tickSpacing, uint160 sqrtPriceX96) external returns (address pool);
    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view returns (address pool);
}
