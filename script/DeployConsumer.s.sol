// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../src/examples/RandomnessConsumer.sol";
import "../src/GoatVRF.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title DeployConsumer
 * @dev Script to deploy the RandomnessConsumer contract and request randomness
 */
contract DeployConsumer is Script {
    function run() external {
        // Load configuration from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address goatVRFAddress = vm.envAddress("GOATVRF_ADDRESS");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy RandomnessConsumer
        RandomnessConsumer consumer = new RandomnessConsumer(goatVRFAddress);
        console.log("RandomnessConsumer deployed at:", address(consumer));

        // Get the fee token address from GoatVRF
        address tokenAddress = IGoatVRF(goatVRFAddress).feeToken();
        console.log("Fee token address:", tokenAddress);

        // Get the balance of the token
        uint256 balance = IERC20(tokenAddress).balanceOf(msg.sender);
        console.log("Fee token balance:", balance);

        // Set max gas price and gas used for estimation
        uint256 estimatedGasUsed = 600000;
        uint256 safeGasPrice = 0.01 gwei; // Use a safe gas price for fee estimation

        // Estimate fee using the custom gas price method
        uint256 estimatedFee = IGoatVRF(goatVRFAddress).calculateFeeWithGasPrice(estimatedGasUsed, safeGasPrice);
        console.log("Estimated fee with", safeGasPrice / 1 gwei, "gwei gas price:", estimatedFee);

        // Apply safety factor for estimations
        uint256 safetyFactor = 2;
        uint256 finalEstimatedFee = estimatedFee * safetyFactor;
        console.log("Final estimated fee with safety factor:", finalEstimatedFee);

        // Transfer tokens to the consumer contract
        console.log("Transferring tokens to consumer:", finalEstimatedFee);
        IERC20(tokenAddress).transfer(address(consumer), finalEstimatedFee);
        console.log("Funded consumer contract with tokens");

        // Set max gas price for the request (can be different from estimation gas price)
        uint256 maxGasPrice = 0.01 gwei;

        // Request randomness
        try consumer.getNewRandom(maxGasPrice) returns (uint256 requestId) {
            console.log("Randomness requested with ID:", requestId);
        } catch Error(string memory reason) {
            console.log("Failed to request randomness:", reason);
        } catch (bytes memory) {
            console.log("Failed to request randomness (unknown error)");
        }

        vm.stopBroadcast();
    }
}
