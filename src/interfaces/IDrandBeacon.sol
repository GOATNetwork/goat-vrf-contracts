// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IDrandBeacon
 * @dev Interface for drand beacon verification
 */
interface IDrandBeacon {
    /**
     * @dev Verify a beacon round signature
     * @param round The round number to verify
     * @param signature The signature to verify
     * @notice Reverts if the signature is invalid
     */
    function verifyBeaconRound(uint256 round, bytes calldata signature) external view;

    /**
     * @dev Get the public key hash of the beacon
     * @return The public key hash
     */
    function publicKeyHash() external view returns (bytes32);

    /**
     * @dev Get the original public key of the beacon
     * @return The public key as bytes
     */
    function publicKey() external view returns (bytes memory);

    /**
     * @dev Get the genesis timestamp of the beacon
     * @return The genesis timestamp
     */
    function genesisTimestamp() external view returns (uint256);

    /**
     * @dev Get the period of the beacon
     * @return The period in seconds
     */
    function period() external view returns (uint256);
}
