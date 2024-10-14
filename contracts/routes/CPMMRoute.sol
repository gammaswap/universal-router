// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@gammaswap/v1-periphery/contracts/base/Transfers.sol";
import '../interfaces/IProtocolRoute.sol';

abstract contract CPMMRoute is IProtocolRoute, Transfers {

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal virtual pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'CPMMRoute: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'CPMMRoute: ZERO_ADDRESS');
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal virtual pure returns (uint256 amountB) {
        require(amountA > 0, 'CPMMRoute: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'CPMMRoute: INSUFFICIENT_LIQUIDITY');
        amountB = amountA * reserveB / reserveA;
    }

    function getGammaPoolAddress(address cfmm, uint16 protocolId) internal override virtual view returns(address) {
        return address(0);
    }

    function sendTokensCallback(address[] calldata tokens, uint256[] calldata amounts, address payee, bytes calldata data) external virtual override {
    }
}
