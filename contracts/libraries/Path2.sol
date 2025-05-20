// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import './BytesLib2.sol';

/// @title Functions for manipulating path data for multihop swaps
library Path2 {
    using BytesLib2 for bytes;

    /// @dev Buffer bytes to separate elements of array in multi path
    bytes constant tag25bytes = hex'00000000000000000000000000000000000000000000000000';

    /// @dev The length of the bytes encoded in tag denoting path is element of array
    uint256 private constant WEIGHT_TAG = 8;
    /// @dev The length of the bytes encoded address
    uint256 private constant ADDR_SIZE = 20;
    /// @dev The length of the bytes encoded in tag denoting path is element of array
    uint256 private constant ARRAY_TAG = WEIGHT_TAG + ADDR_SIZE;
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

    /// @notice Get first token in path (token of the amountIn)
    /// @param path The swap path
    /// @return The first token in the swap path
    function getTokenIn(bytes memory path) internal pure returns (address) {
        return path.toAddress(0);
    }

    /// @notice Get last token in path (token of the amountOut)
    /// @param path The swap path
    /// @return The last token in the swap path
    function getTokenOut(bytes memory path) internal pure returns (address) {
        return path.toAddress(path.length - ADDR_SIZE);
    }

    /// @notice Calculate the number of paths in a multi path swap path
    /// @dev Finds the smallest valid k such that L = 28k + 25n with n >= 1
    /// @param path - The multi path swap path
    /// @return k - The number of paths in the multipath swap path
    function numOfPaths(bytes memory path) internal pure returns (uint256 k) {
        require(path.length >= 53, "INVALID_SPLIT_PATH");
        uint256 length = path.length;
        uint256 modInv28 = 17; // 28^-1 mod 25

        // Initial k mod 25
        uint256 baseK = (modInv28 * length) % NEXT_OFFSET;
        // Try successive values of k = baseK + 25*t
        for (uint256 t = 0; t < 255; t++) {
            k = baseK + NEXT_OFFSET * t;
            if (k == 0) continue; // k must be >= 1

            uint256 remainder = length >= ARRAY_TAG * k ? length - ARRAY_TAG * k : 0;
            if (remainder % NEXT_OFFSET == 0) {
                uint256 n = remainder / NEXT_OFFSET;
                if (n >= 1) {
                    return k;
                }
            }
        }

        revert("No valid k found for given length");
    }

    /// @dev Convert multi path swap path to array of single paths
    /// @param path - The multi path swap path
    /// @return paths - array of single paths in multi path swap path
    /// @return weights - weights to swap in each swap path
    function toPathsAndWeightsArray(bytes memory path) internal view returns (bytes[] memory paths, uint256[] memory weights) {
        uint256 pathCount = numOfPaths(path);
        paths = new bytes[](pathCount);
        weights = new uint256[](pathCount);
        bytes memory pathK = new bytes(0);
        uint256 k = 0;
        uint256 i = 0;
        while (i + ARRAY_TAG <= path.length) {
            weights[k] = path.toUint64(i);
            unchecked { i += WEIGHT_TAG; }

            address tokenIn = path.toAddress(i);
            unchecked { i += ADDR_SIZE; }
            pathK = abi.encodePacked(tokenIn);

            // Read protocolId + feeSize + tokenOut pairs
            // If next 25 bytes is of zero blocks then it's a new element of the array of paths
            while (i + NEXT_OFFSET <= path.length && !isZeroBlock(path, i)) {
                pathK = abi.encodePacked(pathK,path.toUint16(i));
                unchecked { i += PROTOCOL_ID_SIZE; }

                pathK = abi.encodePacked(pathK,path.toUint24(i));
                unchecked { i += FEE_SIZE; }

                pathK = abi.encodePacked(pathK,path.toAddress(i));
                unchecked { i += ADDR_SIZE; }
            }

            // If zero block found, skip it
            if (i + NEXT_OFFSET <= path.length && isZeroBlock(path, i)) {
                validatePath(pathK);
                paths[k] = pathK;
                unchecked {
                    i += NEXT_OFFSET;
                    ++k;
                }
            }
        }
        validatePath(pathK);
        paths[k] = pathK;
    }

    /// @dev convert paths and weights array into a multi path bytes object
    /// @param paths - array of single paths in multi path swap path
    /// @param weights - weights to swap in each swap path
    /// @return path - The multi path swap path
    function fromPathsAndWeightsArray(bytes[] memory paths, uint256[] memory weights) internal view returns(bytes memory path) {
        uint256 len = paths.length;
        require(len == weights.length, "INVALID_WEIGHT_LENGTH");
        for(uint256 i = 0; i < len;) {
            if(i == 0) {
                path = abi.encodePacked(uint64(weights[i]),paths[i]);
            } else {
                path = abi.encodePacked(path,tag25bytes,uint64(weights[i]),paths[i]);
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Returns true if path is single path format
    function isSinglePath(bytes memory path) internal pure returns(bool) {
        return path.length >= 45 && (path.length - 20) % 25 == 0;
    }

    /// @dev Validate single paths
    function validatePath(bytes memory path) internal pure {
        require(isSinglePath(path), "INVALID_PATH");
    }

    /// @dev Check if next 25 bytes in data is made up of only zero bytes
    /// @param data - sequence of bytes
    /// @param offset - offset of data
    /// @return true if next 25 bytes is made up of zero bytes
    function isZeroBlock(bytes memory data, uint256 offset) internal pure returns (bool) {
        return offset + NEXT_OFFSET <= data.length && data.toUint200(offset) == 0;
    }
}