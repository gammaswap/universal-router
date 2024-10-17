// SPDX-License-Identifier: GPL-v3
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../../contracts/test/Token.sol";

contract TokensSetup is Test {
    Token weth;
    Token usdc;
    Token usdt;
    Token dai;
    Token wbtc;

    function initTokens() public {
        weth = new Token("Wrapped ETH", "WETH", 18);
        usdc = new Token("USD Coin", "USDC", 6);
        usdt = new Token("Tether USD", "USDT", 6);
        dai = new Token("DAI", "DAI", 18);
        wbtc = new Token("Wrapped BTC", "WBTC", 8);

        address[] memory _tokens = new address[](5);
        _tokens[0] = address(usdc);
        _tokens[1] = address(weth);
        _tokens[2] = address(usdt);
        _tokens[3] = address(dai);
        _tokens[4] = address(wbtc);
        _tokens = quickSort(_tokens);

        // wbtc < weth < dai < usdt < usdc
        wbtc = Token(_tokens[0]);
        weth = Token(_tokens[1]);
        dai = Token(_tokens[2]);
        usdt = Token(_tokens[3]);
        usdc = Token(_tokens[4]);
        wbtc.setMetaData("Wrapped BTC", "WBTC", 8);
        weth.setMetaData("Wrapped Ethereum", "WETH", 18);
        dai.setMetaData("DAI", "DAI", 18);
        usdt.setMetaData("Tether USD", "USDT", 6);
        usdc.setMetaData("USD Coin", "USDC", 6);
    }

    function sort(address[] memory arr, int left, int right) internal pure {
        int i = left;
        int j = right;
        if(i == j) return;
        address pivot = arr[uint(left + (right - left) / 2)];
        while (i <= j) {
            while (arr[uint(i)] < pivot) i++;
            while (pivot < arr[uint(j)]) j--;
            if (i <= j) {
                (arr[uint(i)], arr[uint(j)]) = (arr[uint(j)], arr[uint(i)]);
                i++;
                j--;
            }
        }
        if (left < j)
            sort(arr, left, j);
        if (i < right)
            sort(arr, i, right);
    }

    // Helper function to start the sorting
    function quickSort(address[] memory arr) public pure returns (address[] memory) {
        sort(arr, 0, int(arr.length - 1));
        return arr;
    }
}