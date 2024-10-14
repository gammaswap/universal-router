// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@gammaswap/v1-core/contracts/libraries/GammaSwapLibrary.sol";
import "@gammaswap/v1-periphery/contracts/interfaces/external/IWETH.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import './interfaces/IAeroPool.sol';
import './BaseRouter.sol';

contract UniversalRouter is BaseRouter {

    using Path2 for bytes;
    using BytesLib2 for bytes;

    constructor(address _WETH) BaseRouter(_WETH) {
    }

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'DeltaSwapRouter: EXPIRED');
        _;
    }

    /// @dev this supports transfer fees tokens too
    function calcRoutes(uint256 amountIn, bytes memory path, address _to) public virtual view returns (Route[] memory routes) {
        require(path.length >= 45 && (path.length - 20) % 25 == 0, "INVALID_PATH");
        routes = new Route[](path.numPools() + 1);
        // transferFrom here first
        uint256 i = 0;
        while (true) {
            bool hasMultiplePools = path.hasMultiplePools();

            routes[i] = Route({
                pair: address(0),
                from: address(0),
                to: address(0),
                protocolId: 0,
                fee: 0,
                dest: _to,
                hop: address(0)
            });

            // only the first pool in the path is necessary
            (routes[i].from, routes[i].to, routes[i].protocolId, routes[i].fee) = path.getFirstPool().decodeFirstPool();

            routes[i].hop = protocols[routes[i].protocolId];
            require(routes[i].hop != address(0), "PROTOCOL_NOT_SET");

            address dest;
            (routes[i].pair, dest) = IProtocolRoute(routes[i].hop).getDestination(routes[i].from,
                routes[i].to, routes[i].fee);

            if(i > 0) {
                routes[i - 1].dest = dest;
            }

            // decide whether to continue or terminate
            if (hasMultiplePools) {
                path = path.skipToken();
            } else {
                break;
            }
            unchecked {
                ++i;
            }
        }
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens2(Route[] memory routes) internal virtual {
        for (uint256 i; i < routes.length - 1; i++) {
            IProtocolRoute(routes[i].hop).swap(routes[i].from, routes[i].to, routes[i].fee, routes[i].dest);
        }
    }
    /// @dev this is the main function we'll use to swap
    function swapExactTokensForTokensSupportingFeeOnTransferTokens2(
        uint256 amountIn,
        uint256 amountOutMin,
        bytes calldata path,
        address to,
        uint256 deadline
    ) external virtual /*override*/ ensure(deadline) {
        Route[] memory routes = calcRoutes(amountIn, path, to);
        GammaSwapLibrary.safeTransferFrom(routes[0].from, msg.sender, routes[0].dest, amountIn);
        uint256 balanceBefore = IERC20(routes[routes.length - 1].to).balanceOf(to);
        _swapSupportingFeeOnTransferTokens2(routes);
        require(
            IERC20(routes[path.length - 1].to).balanceOf(to) - balanceBefore >= amountOutMin,
            'UniversalRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }

    function pay(
        address token,
        address payer,
        address recipient,
        uint256 value
    ) internal {
        if (token == WETH && address(this).balance >= value) {
            // pay with WETH
            IWETH(WETH).deposit{value: value}(); // wrap only what is needed to pay
            IWETH(WETH).transfer(recipient, value);
        } else if (payer == address(this)) {
            // pay with tokens already in the contract (for the exact input multihop case)
            GammaSwapLibrary.safeTransfer(token, recipient, value);
        } else {
            // pull payment
            GammaSwapLibrary.safeTransferFrom(token, payer, recipient, value);
        }
    }
}
