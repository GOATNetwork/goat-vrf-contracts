// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "../src/GoatVRF.sol";
import "../src/FixedFeeRule.sol";
import "../src/BN254DrandBeacon.sol";
import "../src/BLS12381DrandBeacon.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC1967} from "@openzeppelin/contracts/interfaces/IERC1967.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

/**
 * @title Deploy
 * @dev Script to deploy the GoatVRF service and its dependencies
 *
 * Updated features in GoatVRF:
 * - Enhanced balance and allowance checks in requestRandomness
 * - Removed try-catch in fulfillRandomness (payments will revert transaction if they fail)
 * - Only the requester can cancel a request (owner cannot cancel anymore)
 * - Added request expiration time to automatically expire requests after a certain period
 * - Fulfillment will revert if the request has expired
 * - No more debt creation when request is canceled
 */
contract Deploy is Script {
    // ERC1967 implementation storage slot
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function run() external {
        // Load configuration from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address wgoatbtcAddress = vm.envAddress("WGOATBTC_ADDRESS");
        address feeRecipient = vm.envAddress("FEE_RECIPIENT");
        address relayer = vm.envAddress("RELAYER_ADDRESS");

        // FixedFeeRule configuration
        uint256 fixedFee = vm.envUint("FIXED_FEE"); // in wei
        uint256 overheadGas = vm.envUint("OVERHEAD_GAS");

        // GoatVRF configuration
        uint256 maxDeadlineDelta = vm.envUint("MAX_DEADLINE_DELTA"); // in seconds
        uint256 requestExpireTime = vm.envUint("REQUEST_EXPIRE_TIME"); // in seconds

        // Beacon configuration
        string memory beaconType = vm.envString("BEACON_TYPE"); // "BN254" or "BLS12381"
        bytes memory publicKey = vm.envBytes("BEACON_PUBLIC_KEY");
        uint256 genesisTimestamp = vm.envUint("BEACON_GENESIS_TIMESTAMP");
        uint256 period = vm.envUint("BEACON_PERIOD");

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy appropriate beacon based on configuration
        address beacon;
        console.log("Deploying beacon...");
        if (keccak256(bytes(beaconType)) == keccak256(bytes("BN254"))) {
            beacon = address(new BN254DrandBeacon(publicKey, genesisTimestamp, period));
        } else if (keccak256(bytes(beaconType)) == keccak256(bytes("BLS12381"))) {
            // BLS12381 requires 256 bytes public key
            require(publicKey.length == 256, "Invalid BLS12381 public key length");
            beacon = address(new BLS12381DrandBeacon(publicKey, genesisTimestamp, period));
        } else {
            revert("Invalid beacon type");
        }
        console.log("Beacon deployed at:", beacon);

        // Deploy FixedFeeRule
        console.log("Deploying fee rule...");
        FixedFeeRule feeRule = new FixedFeeRule(fixedFee);
        console.log("Fee rule deployed at:", address(feeRule));

        // Deploy proxy
        console.log("Deploying proxy...");
        // Create Options struct with the same settings as in the test
        Options memory opts;
        opts.unsafeAllow = "state-variable-immutable";

        address proxy = Upgrades.deployUUPSProxy(
            "GoatVRF.sol:GoatVRF",
            abi.encodeWithSelector(
                GoatVRF.initialize.selector,
                beacon, // beacon
                wgoatbtcAddress, // wgoatbtcToken
                feeRecipient, // feeRecipient
                relayer, // relayer
                address(feeRule), // feeRule
                maxDeadlineDelta, // maxDeadlineDelta
                overheadGas, // overheadGas
                requestExpireTime // requestExpireTime
            ),
            opts
        );
        console.log("Proxy deployed at:", address(proxy));

        // Verify the proxy was initialized correctly
        console.log("Verifying proxy initialization...");
        GoatVRF proxyContract = GoatVRF(address(proxy));

        try proxyContract.wgoatbtcToken() returns (address tokenAddr) {
            console.log("[SUCCESS] Proxy initialized successfully!");
            console.log("WGOATBTC Token from proxy:", tokenAddr);

            if (tokenAddr != wgoatbtcAddress) {
                console.log("[WARNING] Token address mismatch!");
                console.log("Expected:", wgoatbtcAddress);
                console.log("Actual:", tokenAddr);
            }
        } catch Error(string memory reason) {
            console.log("[ERROR] Failed to initialize proxy:", reason);
        } catch (bytes memory) {
            console.log("[ERROR] Failed to initialize proxy (unknown error)");
        }

        // Check other configuration values
        try proxyContract.beacon() returns (address beaconAddr) {
            console.log("Beacon from proxy:", beaconAddr);
            if (beaconAddr != beacon) {
                console.log("[WARNING] Beacon address mismatch!");
            }
        } catch {
            console.log("[ERROR] Failed to get beacon address from proxy");
        }

        try proxyContract.feeRecipient() returns (address recipientAddr) {
            console.log("Fee Recipient from proxy:", recipientAddr);
            if (recipientAddr != feeRecipient) {
                console.log("[WARNING] Fee recipient address mismatch!");
            }
        } catch {
            console.log("[ERROR] Failed to get fee recipient address from proxy");
        }

        try proxyContract.relayer() returns (address relayerAddr) {
            console.log("Relayer from proxy:", relayerAddr);
            if (relayerAddr != relayer) {
                console.log("[WARNING] Relayer address mismatch!");
            }
        } catch {
            console.log("[ERROR] Failed to get relayer address from proxy");
        }

        try proxyContract.feeRule() returns (address feeRuleAddr) {
            console.log("Fee Rule from proxy:", feeRuleAddr);
            if (feeRuleAddr != address(feeRule)) {
                console.log("[WARNING] Fee rule address mismatch!");
            }
        } catch {
            console.log("[ERROR] Failed to get fee rule address from proxy");
        }

        try proxyContract.overheadGas() returns (uint256 gas) {
            console.log("Overhead Gas from proxy:", gas);
            if (gas != overheadGas) {
                console.log("[WARNING] Overhead gas mismatch!");
            }
        } catch {
            console.log("[ERROR] Failed to get overhead gas from proxy");
        }

        try proxyContract.requestExpireTime() returns (uint256 expireTime) {
            console.log("Request Expire Time from proxy:", expireTime);
            if (expireTime != requestExpireTime) {
                console.log("[WARNING] Request expire time mismatch!");
            }
        } catch {
            console.log("[ERROR] Failed to get request expire time from proxy");
        }

        // Check if the proxy is correctly set up
        // Read implementation address directly from storage slot
        address implAddr = StorageSlot.getAddressSlot(IMPLEMENTATION_SLOT).value;
        console.log("Implementation address from proxy:", implAddr);

        console.log("Deployment Summary:");
        console.log("-------------------");
        console.log("WGOATBTC:", wgoatbtcAddress);
        console.log("Beacon Type:", beaconType);
        console.log("Beacon:", beacon);
        console.log("FeeRule:", address(feeRule));
        console.log("Fee Recipient:", feeRecipient);
        console.log("Relayer:", relayer);
        console.log("Fixed Fee:", fixedFee);
        console.log("Overhead Gas:", overheadGas);
        console.log("Max Deadline Delta:", maxDeadlineDelta);
        console.log("Request Expire Time:", requestExpireTime);
        console.log("GoatVRF Proxy:", address(proxy));

        vm.stopBroadcast();
    }
}
