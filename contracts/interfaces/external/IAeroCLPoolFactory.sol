pragma solidity ^0.8.0;

interface IAeroCLPoolFactory {
    function setOwner(address _owner) external virtual;
    function setSwapFeeModule(address _swapFeeModule) external virtual;
    function setUnstakedFeeModule(address _unstakedFeeModule) external virtual;
    function setSwapFeeManager(address _swapFeeManager) external virtual;
    function setUnstakedFeeManager(address _unstakedFeeManager) external virtual;
}
