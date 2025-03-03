// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IDrandBeacon.sol";
import "../interfaces/IRandomnessCallback.sol";
import "../interfaces/IGoatVRF.sol";

/**
 * @title RandomnessConsumer
 * @dev Example contract demonstrating how to consume randomness from GoatVRF
 */
contract RandomnessConsumer is Ownable, IRandomnessCallback {
    // GoatVRF contract address
    address public goatVRF;

    // Random number storage
    mapping(uint256 => uint256) public randomResults;

    // Events
    event RandomnessRequested(uint256 indexed requestId);
    event RandomnessReceived(uint256 indexed requestId, uint256 randomness);

    /**
     * @dev Constructor
     * @param goatVRF_ Address of the GoatVRF contract
     */
    constructor(address goatVRF_) Ownable(msg.sender) {
        goatVRF = goatVRF_;
    }

    /**
     * @dev Update the GoatVRF contract address
     * @param goatVRF_ New GoatVRF contract address
     */
    function setGoatVRF(address goatVRF_) external onlyOwner {
        goatVRF = goatVRF_;
    }

    /**
     * @dev Request randomness from GoatVRF
     * @param maxAllowedGasPrice Maximum allowed gas price for fulfillment
     * @return requestId Unique identifier for the request
     */
    function getNewRandom(uint256 maxAllowedGasPrice) external onlyOwner returns (uint256 requestId) {
        // Get the WGOATBTC token address from GoatVRF
        address tokenAddress = IGoatVRF(goatVRF).wgoatbtcToken();

        // Calculate fee with sufficient gas for callback
        // The callback is simple, but we allocate extra gas to be safe
        uint256 fee = IGoatVRF(goatVRF).calculateFee(600000);

        // Transfer tokens from caller to this contract if needed
        // This step is optional depending on your token handling strategy

        // Approve GoatVRF to spend tokens
        IERC20 token = IERC20(tokenAddress);
        uint256 safetyMargin = fee * 3 / 2; // 50% safety margin
        require(token.approve(goatVRF, safetyMargin), "Token approval failed");

        // Get beacon for deadline calculation
        IDrandBeacon beacon = IDrandBeacon(IGoatVRF(goatVRF).beacon());

        // Request randomness with appropriate deadline
        uint256 deadline = block.timestamp + beacon.period();
        requestId = IGoatVRF(goatVRF).getNewRandom(deadline, maxAllowedGasPrice, 600000);
    }

    /**
     * @dev Callback function used by GoatVRF to deliver randomness
     * @param requestId Unique identifier for the randomness request
     * @param randomness The random value
     */
    function receiveRandomness(uint256 requestId, uint256 randomness) external override {
        // Only GoatVRF can call this function
        require(msg.sender == goatVRF, "Only GoatVRF can fulfill randomness");

        // Store the result
        randomResults[requestId] = randomness;

        // Emit event
        emit RandomnessReceived(requestId, randomness);
    }

    /**
     * @dev Cancel a randomness request
     * @param requestId Unique identifier for the request to cancel
     */
    function cancelRequest(uint256 requestId) external onlyOwner {
        IGoatVRF(goatVRF).cancelRequest(requestId);
    }

    /**
     * @dev Recover any tokens accidentally sent to this contract
     * @param token_ Address of the token to recover
     * @param amount Amount of tokens to recover
     * @param recipient Address to send the tokens to
     */
    function recoverTokens(address token_, uint256 amount, address recipient) external onlyOwner {
        IERC20(token_).transfer(recipient, amount);
    }

    /**
     * @dev Get a specific random result
     * @param requestId Unique identifier for the randomness request
     * @return The random value
     */
    function getRandomResult(uint256 requestId) external view returns (uint256) {
        return randomResults[requestId];
    }
}
