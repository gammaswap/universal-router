pragma solidity ^0.8.0;

interface ICLGaugeFactory {
    function setNonfungiblePositionManager(address _nonfungiblePositionManager) external virtual;
    function setNotifyAdmin(address _notifyAdmin) external virtual;
}
