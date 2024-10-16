// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Random {
    // Generate a pseudo-random number using block attributes
    function getRandomNumber(uint256 max, uint256 nonce) public view returns (uint256) {
        // Adding a nonce to ensure different random values on each call
        return uint256(keccak256(abi.encodePacked(block.timestamp, block.difficulty, msg.sender, nonce))) % max;
    }

    // Fisher-Yates shuffle to randomize a list of unique numbers
    function shuffleAddresses(address[] memory array, uint128 nonce) public view returns (address[] memory) {
        uint256 n = array.length;
        for (uint256 i = n - 1; i > 0; i--) {
            // Generate a random index using the block attributes
            uint256 j = getRandomNumber(i + 1, nonce + i);

            // Swap elements at i and j
            address temp = array[i];
            array[i] = array[j];
            array[j] = temp;
        }
        return array;
    }
}