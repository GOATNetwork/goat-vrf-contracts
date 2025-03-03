// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../interfaces/IDrandBeacon.sol";

contract MockDrandBeacon is IDrandBeacon {
    uint256 private _genesisTimestamp;
    uint256 private _period;
    bytes private _publicKey;
    bytes32 private _publicKeyHash;

    constructor() {
        _genesisTimestamp = block.timestamp;
        _period = 30; // 30 seconds period
        _publicKey =
            hex"868f005eb8e6e4ca0a47c8a77ceaa5309a47978a7c71bc5cce96366b5d7a569937c529eeda66c7293784a9402801af31";
        _publicKeyHash = keccak256(_publicKey);
    }

    function verifyBeaconRound(uint256 round, bytes calldata signature) external pure override {
        // Mock implementation always verifies successfully
        // In production, this would verify the BLS signature
    }

    function genesisTimestamp() external view override returns (uint256) {
        return _genesisTimestamp;
    }

    function period() external view override returns (uint256) {
        return _period;
    }

    function publicKey() external view override returns (bytes memory) {
        return _publicKey;
    }

    function publicKeyHash() external view override returns (bytes32) {
        return _publicKeyHash;
    }
}
