// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import './BytesLib2.sol';

/// @title Functions for manipulating path data for multihop swaps
library Path2 {
    using BytesLib2 for bytes;

    /// @dev The length of the bytes encoded address
    uint256 private constant ADDR_SIZE = 20;
    /// @dev The length of the bytes encoded protocol ID
    uint256 private constant PROTOCOL_ID_SIZE = 2;
    /// @dev The length of the bytes encoded fee (for V3 pools)
    uint256 private constant FEE_SIZE = 3;

    /// @dev The offset of a single token address, protocol ID, and pool fee
    uint256 private constant NEXT_OFFSET = ADDR_SIZE + PROTOCOL_ID_SIZE + FEE_SIZE;
    /// @dev The offset of an encoded pool key
    uint256 private constant POP_OFFSET = NEXT_OFFSET + ADDR_SIZE;
    /// @dev The minimum length of an encoding that contains 2 or more pools
    uint256 private constant MULTIPLE_POOLS_MIN_LENGTH = POP_OFFSET + NEXT_OFFSET;

    /// @notice Returns true iff the path contains two or more pools
    /// @param path The encoded swap path
    /// @return True if path contains two or more pools, otherwise false
    function hasMultiplePools(bytes memory path) internal pure returns (bool) {
        return path.length >= MULTIPLE_POOLS_MIN_LENGTH;
    }

    /// @notice Returns the number of pools in the path
    /// @param path The encoded swap path
    /// @return The number of pools in the path
    function numPools(bytes memory path) internal pure returns (uint256) {
        // Ignore the first token address. From then on every fee and token offset indicates a pool.
        return ((path.length - ADDR_SIZE) / NEXT_OFFSET);
    }

    /// @notice Decodes the first pool in path
    /// @param path The bytes encoded swap path
    /// @return tokenA The first token of the given pool
    /// @return tokenB The second token of the given pool
    /// @return protocolId The protocol ID of the AMM
    /// @return fee The fee level of the pool
    function decodeFirstPool(bytes memory path)
    internal
    pure
    returns (
        address tokenA,
        address tokenB,
        uint16 protocolId,
        uint24 fee
    )
    {
        tokenA = path.toAddress(0);
        protocolId = path.toUint16(ADDR_SIZE);
        fee = path.toUint24(ADDR_SIZE + PROTOCOL_ID_SIZE);
        tokenB = path.toAddress(NEXT_OFFSET);
    }

    /// @notice Gets the segment corresponding to the last pool in the path
    /// @param path The bytes encoded swap path
    /// @return The segment containing all data necessary to target the last pool in the path
    function getLastPool(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(path.length - POP_OFFSET, POP_OFFSET);
    }

    /// @notice Gets the segment corresponding to the first pool in the path
    /// @param path The bytes encoded swap path
    /// @return The segment containing all data necessary to target the first pool in the path
    function getFirstPool(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(0, POP_OFFSET);
    }

    /// @notice Skips a token + protocolId + fee element from the buffer and returns the remainder
    /// @param path The swap path
    /// @return The remaining token + protocolId + fee elements in the path
    function skipToken(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(NEXT_OFFSET, path.length - NEXT_OFFSET);
    }

    /// @notice Hop a token + protocolId + fee element from the buffer and returns the remainder
    /// @param path The swap path
    /// @return The remaining token + protocolId + fee elements in the path
    function hopToken(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(0, path.length - NEXT_OFFSET);
    }
}