// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.8.0;

import '@gammaswap/v1-periphery/contracts/base/Transfers.sol';
import '../interfaces/IProtocolRoute.sol';

/// @title CPMM Route base abstract contract
/// @author Daniel D. Alcarraz (https://github.com/0xDanr)
/// @notice Implements functions used by all protocol route contracts
abstract contract CPMMRoute is IProtocolRoute, Transfers {

    /// @inheritdoc IProtocolRoute
    uint16 public immutable override protocolId;

    /// @inheritdoc IProtocolRoute
    address public immutable override factory;

    /// @dev returns sorted token addresses, used to handle return values from pairs sorted in this order
    /// @param tokenA - address of first ERC20 token
    /// @param tokenB - address of second ERC20 token
    /// @return token0 - address lower in numerical value
    /// @return token1 - address higher in numerical value
    function _sortTokens(address tokenA, address tokenB) internal virtual pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'CPMMRoute: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'CPMMRoute: ZERO_ADDRESS');
    }

    /// @dev Given some amount of an asset and pair reserves, returns an equivalent amount of the other asset based on marginal price
    /// @param amountA - amount of tokenA
    /// @param reserveA - reserve amount in AMM of tokenA
    /// @param reserveB - reserve amount in AMM of tokenB
    /// @return amountB - amountB of tokenB that is equivalent to amountA of tokenA
    function _quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal virtual pure returns (uint256 amountB) {
        require(amountA > 0, 'CPMMRoute: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'CPMMRoute: INSUFFICIENT_LIQUIDITY');
        amountB = amountA * reserveB / reserveA;
    }

    /// @inheritdoc Transfers
    function getGammaPoolAddress(address, uint16) internal override virtual view returns(address) {
        return address(0);
    }

    /// @inheritdoc ISendTokensCallback
    function sendTokensCallback(address[] calldata tokens, uint256[] calldata amounts, address payee, bytes calldata data) external virtual override {
    }
}
