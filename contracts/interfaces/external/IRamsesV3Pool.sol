// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IRamsesV3PoolImmutables} from './shadow-cl/IRamsesV3PoolImmutables.sol';
import {IRamsesV3PoolState} from './shadow-cl/IRamsesV3PoolState.sol';
import {IRamsesV3PoolDerivedState} from './shadow-cl/IRamsesV3PoolDerivedState.sol';
import {IRamsesV3PoolActions} from './shadow-cl/IRamsesV3PoolActions.sol';
import {IRamsesV3PoolOwnerActions} from './shadow-cl/IRamsesV3PoolOwnerActions.sol';
import {IRamsesV3PoolErrors} from './shadow-cl/IRamsesV3PoolErrors.sol';
import {IRamsesV3PoolEvents} from './shadow-cl/IRamsesV3PoolEvents.sol';

/// @title The interface for a Ramses V3 Pool
/// @notice A Ramses pool facilitates swapping and automated market making between any two assets that strictly conform
/// to the ERC20 specification
/// @dev The pool interface is broken up into many smaller pieces
interface IRamsesV3Pool is
    IRamsesV3PoolImmutables,
    IRamsesV3PoolState,
    IRamsesV3PoolDerivedState,
    IRamsesV3PoolActions,
    IRamsesV3PoolOwnerActions,
    IRamsesV3PoolErrors,
    IRamsesV3PoolEvents
{
    /// @notice if a new period, advance on interaction
    function _advancePeriod() external;
}