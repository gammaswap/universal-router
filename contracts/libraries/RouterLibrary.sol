// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library RouterLibrary {

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path) internal view returns (uint256[] memory amounts) {
        /*require(path.length >= 2, 'RouterLibrary: INVALID_PATH');
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut, address pair) = getReserves(factory, path[i], path[i + 1]);
            uint256 fee = calcPairTradingFee(amounts[i], reserveIn, reserveOut, pair);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut, fee);
        }/**/
    }
}
