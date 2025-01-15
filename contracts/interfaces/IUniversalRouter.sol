// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

/// @title Universal Router Interface
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Interface for UniversalRouter contract
interface IUniversalRouter {

    /// @dev emitted when a protocol route is added
    event AddProtocolRoute(uint16 indexed protocolId, address protocol);
    /// @dev emitted when a protocol route is removed
    event RemoveProtocolRoute(uint16 indexed protocolId, address protocol);
    /// @dev emitted when a pair is tracked
    event TrackPair(address indexed pair, address token0, address token1, uint24 fee, address factory, uint16 protocolId);
    /// @dev emitted when a pair is un-tracked
    event UnTrackPair(address indexed pair, address token0, address token1, uint24 fee, address factory, uint16 protocolId);

    /// @dev Route struct that contains instructions to perform a swap through supported routes
    struct Route {
        /// @dev AMM of protocol to perform swap
        address pair;
        /// @dev token to swap from
        address from;
        /// @dev token to swap to
        address to;
        /// @dev ID of supported protocol route (e.g. AMM's protocol)
        uint16 protocolId;
        /// @dev fee associated with AMM
        uint24 fee;
        /// @dev address that will receive the output of each AMM swap
        address destination;
        /// @dev address that will send the input of each AMM swap
        address origin;
        /// @dev address of IProtocolRoute contract for each AMM swap
        address hop;
    }

    /// @dev function to initialize contract storage variables
    function initialize() external;

    /// @dev Get protocol route identified by protocolId from supported routes
    /// @param protocolId - protocolId identifying route to retrieve
    /// @return address of supported protocol route contract (IProtocolRoute implementation)
    function protocolRoutes(uint16 protocolId) external view returns(address);

    /// @dev Add protocol route identified by protocolId to supported routes
    /// @param protocol - address of protocol route contract
    function addProtocolRoute(address protocol) external;

    /// @dev Remove protocol route identified by protocolId from supported routes
    /// @param protocolId - protocolId identifying route to remove
    function removeProtocolRoute(uint16 protocolId) external;

    /// @dev Swap ETH for ERC20 token at path[n] through provided path. Token at path[0] must be WETH
    /// @dev Must transfer ETH when calling this function to perform swap
    /// @param amountOutMin - minimum quantity of token at path[n] willing to receive or revert
    /// @param path - path of tokens to perform swap
    /// @param to - address to receive output of token swap
    /// @param deadline - timestamp (block.timestamp) after which transaction will expire (revert)
    function swapExactETHForTokens(uint256 amountOutMin, bytes calldata path, address to, uint256 deadline) external payable;

    /// @dev Swap amountIn of ERC20 token at path[0] for ETH through provided path. Token at path[n] must be WETH
    /// @param amountIn - quantity of token at path[0] to swap for token at path[n]
    /// @param amountOutMin - minimum quantity of token at path[n] willing to receive or revert
    /// @param path - path of tokens to perform swap
    /// @param to - address to receive output of token swap
    /// @param deadline - timestamp (block.timestamp) after which transaction will expire (revert)
    function swapExactTokensForETH(uint256 amountIn, uint256 amountOutMin, bytes calldata path, address to, uint256 deadline) external;

    /// @dev Swap amountIn of ERC20 token at path[0] for ERC20 token at path[n] through provided path
    /// @param amountIn - quantity of token at path[0] to swap for token at path[n]
    /// @param amountOutMin - minimum quantity of token at path[n] willing to receive or revert
    /// @param path - path of tokens to perform swap
    /// @param to - address to receive output of token swap
    /// @param deadline - timestamp (block.timestamp) after which transaction will expire (revert)
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, bytes calldata path, address to, uint256 deadline) external;

    /// @dev Calculate array of route instructions from `path` to perform swap across `path`
    /// @param path - path of tokens to perform swap
    /// @param to - address that will receive final output of swap
    /// @return routes - array of route instructions
    function calcRoutes(bytes memory path, address to) external view returns (Route[] memory routes);

    /// @dev Get a quote for amountIn using the marginal price calculated from the path provided (e.g. marginalPrice = path[n]/path[0])
    /// @param amountIn - amount of token in the beginning of the path provided
    /// @param path - path used to calculated marginal price (e.g. path[0] -> path[1] -> ... path[n])
    /// @return amountOut - quantity of token path[n] obtained from swapping amountIn of token path[0] at the marginal price
    function quote(uint256 amountIn, bytes calldata path) external view returns(uint256 amountOut);

    /// @dev Get total fee for executing through given path
    /// @param path - path used to calculate fee (e.g. path[0] -> path[1] -> ... path[n])
    /// @return pathFee - total fee of execution through the path in integer form. Divide by 1e6 to convert to decimal form
    function calcPathFee(bytes calldata path) external view returns(uint256 pathFee);

    /// @dev Expected amounts to get from swapping amountIn of token path[0]. Takes slippage from price impact and fees into account
    /// @param amountIn - amount of token in the beginning of the path provided
    /// @param path - path used to perform the swap (e.g. path[0] -> path[1] -> ... path[n])
    /// @return amounts - amounts of tokens swapped through the path provided
    /// @return routes - array of route parameters to perform swap through the path provided
    function getAmountsOut(uint256 amountIn, bytes memory path) external returns (uint256[] memory amounts, Route[] memory routes);

    /// @dev Expected amounts to provide to obtain amountOut of token path[n]. Takes slippage from price impact and fees into account
    /// @param amountOut - desired amount to get of token[n] when swap finishes
    /// @param path - path used to perform the swap (e.g. path[0] -> path[1] -> ... path[n])
    /// @return amounts - amounts of tokens swapped through the path provided
    /// @return routes - array of route parameters to perform swap through the path provided
    function getAmountsIn(uint256 amountOut, bytes memory path) external returns (uint256[] memory amounts, Route[] memory routes);

    /// @dev Check if already emitted TrackPair event for pair
    /// @param pair - address of AMM tracked
    /// @return timestamp pair started being tracked
    function trackedPairs(address pair) external view returns(uint256);

    /// @dev Emit event detailing AMM for tokenA and tokenB pair so that it's tracked in subgraph.
    /// @param token0 - address of a token of the AMM pool
    /// @param token1 - address of other token of the AMM pool
    /// @param fee - AMM fee used to identify AMM pool
    /// @param protocolId - protocolId identifying route pair belongs to
    function trackPair(address token0, address token1, uint24 fee, uint16 protocolId) external;

    /// @dev Emit event detailing AMM for tokenA and tokenB pair so that it's tracked in subgraph.
    /// @param token0 - address of a token of the AMM pool
    /// @param token1 - address of other token of the AMM pool
    /// @param fee - AMM fee used to identify AMM pool
    /// @param protocolId - protocolId identifying route pair belongs to
    function unTrackPair(address token0, address token1, uint24 fee, uint16 protocolId) external;

    /// @dev Get pair information from tokens, fee, protocolId identifiers
    /// @param tokenA - address of a token of the AMM pool
    /// @param tokenB - address of other token of the AMM pool
    /// @param fee - AMM fee used to identify AMM pool
    /// @param protocolId - protocolId identifying route pair belongs to
    /// @return pair - address of AMM
    /// @return token0 - address of first token in AMM
    /// @return token1 - address of second token in AMM
    /// @return factory - factory contract that created AMM
    function getPairInfo(address tokenA, address tokenB, uint24 fee, uint16 protocolId) external view returns(address pair, address token0, address token1, address factory);
}
