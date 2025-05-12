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

    function generateWeights(uint256 n) public view returns (uint256[] memory weights) {
        require(n > 0 && n <= 256, "Invalid n");

        uint256 ONE = 1e18;
        uint256[] memory cuts = new uint256[](n - 1);
        weights = new uint256[](n);

        // Generate n-1 random cut points
        for (uint256 i = 0; i < n - 1; i++) {
            // Use blockhash or block.timestamp for pseudo-randomness (not secure)
            cuts[i] = getRandomNumber(ONE, i);
        }

        // Sort cuts (in-place insertion sort, cheap for small arrays)
        for (uint256 i = 1; i < cuts.length; i++) {
            uint256 key = cuts[i];
            uint256 j = i;
            while (j > 0 && cuts[j - 1] > key) {
                cuts[j] = cuts[j - 1];
                j--;
            }
            cuts[j] = key;
        }

        // Compute gaps between sorted cuts to get the share sizes
        uint256 last = 0;
        for (uint256 i = 0; i < cuts.length; i++) {
            weights[i] = cuts[i] - last;
            require(weights[i] > 0, "Zero slice"); // optional: remove zeros
            last = cuts[i];
        }

        // Final segment from last cut to ONE
        weights[n - 1] = ONE - last;
        require(weights[n - 1] > 0, "Final slice zero");
    }
}