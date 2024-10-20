// SPDX-License-Identifier: GPL-2.0-or-later
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
}
