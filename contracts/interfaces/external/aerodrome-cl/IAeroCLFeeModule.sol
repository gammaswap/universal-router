// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0;

import "../IAeroCLPoolFactory.sol";

interface IAeroCLFeeModule {
    /// @notice Get the factory that the fee module belongs to
    function factory() external view returns (IAeroCLPoolFactory);

    /// @notice Get fee for a given pool. Accounts for default and dynamic fees
    /// @dev Fee is denominated in bips.
    /// @param pool The pool to get the fee for
    /// @return The fee for the given pool
    function getFee(address pool) external view returns (uint24);
}