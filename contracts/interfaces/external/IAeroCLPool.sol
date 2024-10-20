pragma solidity ^0.8.0;

import "./aerodrome-cl/IAeroCLPoolConstants.sol";
import "./aerodrome-cl/IAeroCLPoolState.sol";
import "./aerodrome-cl/IAeroCLPoolDerivedState.sol";
import "./aerodrome-cl/IAeroCLPoolActions.sol";
import "./aerodrome-cl/IAeroCLPoolOwnerActions.sol";
import "./aerodrome-cl/IAeroCLPoolEvents.sol";

interface IAeroCLPool is
    IAeroCLPoolConstants,
    IAeroCLPoolState,
    IAeroCLPoolDerivedState,
    IAeroCLPoolActions,
    IAeroCLPoolEvents,
    IAeroCLPoolOwnerActions {
    /* /// notice The contract that deployed the pool, which must adhere to the ICLFactory interface
    /// return The contract address
    function factory() external view returns (address);

    /// notice The first of the two tokens of the pool, sorted by address
    /// return The token contract address
    function token0() external view returns (address);

    /// notice The second of the two tokens of the pool, sorted by address
    /// return The token contract address
    function token1() external view returns (address);

    /// notice The pool tick spacing
    /// dev Ticks can only be used at multiples of this value, minimum of 1 and always positive
    /// e.g.: a tickSpacing of 3 means ticks can be initialized every 3rd tick, i.e., ..., -6, -3, 0, 3, 6, ...
    /// This value is an int24 to avoid casting even though it is always positive.
    /// return The tick spacing
    function tickSpacing() external view returns (int24);


    struct Slot0 {
        // the current price
        uint160 sqrtPriceX96;
        // the current tick
        int24 tick;
        // the most-recently updated index of the observations array
        uint16 observationIndex;
        // the current maximum number of observations that are being stored
        uint16 observationCardinality;
        // the next maximum number of observations to store, triggered in observations.write
        uint16 observationCardinalityNext;
        // whether the pool is locked
        bool unlocked;
    }

    Slot0 public slot0;/**/
}
