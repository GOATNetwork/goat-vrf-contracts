// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "../GoatVRF.sol";

/**
 * @title GoatVRFV2UpgradeTest
 * @dev Mock upgraded version of GoatVRF contract with added functionality
 * @custom:oz-upgrades-from GoatVRF
 */
contract GoatVRFV2UpgradeTest is GoatVRF {
    // New variable to test state after upgrade
    string public version;

    // Initialize function for V2 with reinitializer to avoid multiple initialization
    function initialize(string memory _version) public reinitializer(2) {
        // Call parent initializers to satisfy upgrade requirements
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Set version
        version = _version;
    }

    // New function to test new functionality after upgrade
    function setVersion(string memory _version) external onlyOwner {
        version = _version;
    }

    // Get version
    function getVersion() external view returns (string memory) {
        return version;
    }
}
