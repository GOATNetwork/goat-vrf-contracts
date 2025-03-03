// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IRandomnessCallback
 * @dev Interface for contracts that want to receive randomness from GoatVRF
 */
interface IRandomnessCallback {
    /**
     * @dev Called by GoatVRF when randomness is ready
     * @param requestId Unique identifier for the request
     * @param randomness The random value
     */
    function receiveRandomness(uint256 requestId, uint256 randomness) external;
}
