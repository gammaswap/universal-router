// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '@gammaswap/v1-core/contracts/interfaces/periphery/IExternalCallee.sol';

/// @title External Callee interface for Universal Router
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Defines struct passed to externalCall function in data parameter
interface IRouterExternalCallee is IExternalCallee {
    /// @dev Struct to use in externalCall function
    struct ExternalCallData {
        /// @dev amount of token sold
        uint256 amountIn;
        /// @dev min amount expected to get for token sold
        uint256 minAmountOut;
        /// @dev deadline in timestamp seconds
        uint256 deadline;
        /// @dev optional id number to identify transaction
        uint256 tokenId;
        /// @dev path of token swaps. First token in the path corresponds to amountIn, last token in the path corresponds to minAmountOut
        bytes path;
    }

    /// @dev Event emitted after performing a swap by calling externalCall
    event ExternalCallSwap(
        /// @dev optional field to identify address caller called function on behalf
        address indexed sender,
        /// @dev address that called externalCall
        address indexed caller,
        /// @dev optional id number to identify transaction
        uint256 indexed tokenId,
        /// @dev token sold
        address tokenIn,
        /// @dev token bought
        address tokenOut,
        /// @dev amount of tokenIn sold
        uint256 amountIn,
        /// @dev amount of tokenOut bought
        uint256 amountOut);
}
