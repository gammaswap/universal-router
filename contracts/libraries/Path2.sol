// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import './BytesLib2.sol';
import 'forge-std/console.sol';

/// @title Functions for manipulating path data for multihop swaps
library Path2 {
    using BytesLib2 for bytes;

    /// @dev The length of the bytes encoded in tag denoting path is element of array
    uint256 private constant ARRAY_TAG = 1;
    /// @dev The length of the bytes encoded in tag denoting path is element of array
    uint256 private constant WEIGHT_TAG = 2;
    /// @dev The length of the bytes encoded in tag denoting path is element of array
    uint256 private constant NEXT_MULTI_PATH = ARRAY_TAG + WEIGHT_TAG;
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
    /// @dev The minimum length of an encoding that is a multiple path array
    uint256 private constant MULTIPLE_PATHS_MIN_LENGTH = NEXT_MULTI_PATH + POP_OFFSET ;

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

    function hasArrayTag(bytes memory path) internal pure returns (bool) {
        return path.toUint8(0) == 0xff;
    }

    function skipWeightTag(bytes memory path) internal pure returns (bytes memory) {
        return path.slice(WEIGHT_TAG, path.length - WEIGHT_TAG);
    }

    // Finds the smallest valid k such that L = 22k + 25n with n >= 1
    function numOfPaths(bytes memory path) internal pure returns (uint256 k) {
        uint256 length = path.length;
        //console.log("length:",length);
        uint256 modInv21 = 12; // 22^-1 mod 25
        //console.log("modInv21:",modInv21);

        // Initial k mod 25
        uint256 baseK = (modInv21 * length) % 25;
        // Try successive values of k = baseK + 25*t
        for (uint256 t = 0; t < 255; t++) {
            k = baseK + 25 * t;
            if (k == 0) continue; // k must be >= 1

            uint256 remainder = length >= 23 * k ? length - 23 * k : 0;
            if (remainder % 25 == 0) {
                uint256 n = remainder / 25;
                if (n >= 1) {
                    return k;
                }
            }
        }

        revert("No valid k found for given length");
    }

    /*function toPathsAndWeightsArray(bytes memory path) internal pure returns (bytes[] memory paths, uint256[] memory weights) {
        require(hasArrayTag(path), "INVALID_MULTI_PATH");

        uint256 pathCount = numOfPaths(path);
        paths = new bytes[](pathCount);
        weights = new uint256[](pathCount);
        path = skipWeightTag(path);

        uint256 k = 0;
        bytes memory kPath = new bytes(0);

        while(path.length > 0) {
            kPath = abi.encodePacked(kPath,path.slice(0, NEXT_OFFSET));
            path = skipToken(path);
            if(hasArrayTag(path)) {
                paths[k] = kPath;
                path = skipWeightTag(path);
                unchecked {
                    ++k;
                }
            }
        }
    }/**/

    function toPathsAndWeightsArray(bytes memory path) internal view returns (bytes[] memory paths, uint256[] memory weights) {
        uint256 pathCount = numOfPaths(path);
        console.log("pathCount:",pathCount);
        paths = new bytes[](pathCount);
        weights = new uint256[](pathCount);
        bytes memory pathK = new bytes(0);
        uint256 k = 0;
        uint256 i = 0;
        console.log("_pathLen:",path.length);
        while (i + NEXT_MULTI_PATH + ADDR_SIZE <= path.length) {
        //while (i + 3 + 20 <= path.length) {
            bytes1 tag = path[i];
            uint16 weight = path.toUint16(i + ARRAY_TAG);
            i += NEXT_MULTI_PATH;
            //uint16 weight = uint16(bytes2(path[i+1:i+3]));
            //i += 3;

            address tokenIn = path.toAddress(i);
            i += ADDR_SIZE;
            //address tokenIn = address(bytes20(path[i:i+20]));
            //i += 20;

            pathK = abi.encodePacked(tokenIn);
            console.log("k:",k);
            // Read instruction/output pairs
            while (i + NEXT_OFFSET <= path.length) {
            //while (i + 5 + 20 <= path.length) {
                console.log("i:",i);
                // Check if current position marks start of next [tag + weight]
                if (((i - NEXT_MULTI_PATH - ADDR_SIZE) % 25 == 0) && (i + NEXT_MULTI_PATH + ADDR_SIZE <= path.length)) {
                    paths[k] = pathK;
                    weights[k] = weight;
                    unchecked {
                        ++k;
                    }
                    console.log("next_path:",k);
                    break; // Detected start of next path
                }
                //if (((i - 23) % 25 == 0) && (i + 3 + 20 <= path.length)) {
                //    break; // Detected start of next path
                //}

                pathK = abi.encodePacked(pathK,path.toUint16(i));
                i += PROTOCOL_ID_SIZE;

                pathK = abi.encodePacked(pathK,path.toUint24(i));
                i += FEE_SIZE;
                //bytes5 instruction = bytes5(path[i:i+5]);
                //i += 5;

                pathK = abi.encodePacked(pathK,path.toAddress(i));
                i += ADDR_SIZE;
                //address tokenOut = address(bytes20(path[i:i+20]));
                //i += 20;

                // Process the instruction
            }
            // End of one path — loop continues
            console.log("pathLen:",path.length);
        }
    }

    /*function parse(bytes memory data) internal pure {
        uint256 i = 0;
        while (i + 3 + 20 <= data.length) {
            bytes1 tag = data[i];
            uint16 weight = uint16(bytes2(data[i+1:i+3]));
            i += 3;

            address tokenIn = address(bytes20(data[i:i+20]));
            i += 20;

            // Read instruction/output pairs
            while (i + 5 + 20 <= data.length) {
                // Check if current position marks start of next [tag + weight]
                if (((i - 23) % 25 == 0) && (i + 3 + 20 <= data.length)) {
                    break; // Detected start of next path
                }

                bytes5 instruction = bytes5(data[i:i+5]);
                i += 5;

                address tokenOut = address(bytes20(data[i:i+20]));
                i += 20;

                // Process the instruction
            }

            // End of one path — loop continues
        }
    }/**/
}