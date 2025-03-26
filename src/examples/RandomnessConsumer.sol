// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IDrandBeacon.sol";
import "../interfaces/IRandomnessCallback.sol";
import "../interfaces/IGoatVRF.sol";

/**
 * @title RandomnessConsumer
 * @dev Example contract demonstrating how to consume randomness from GoatVRF
 */
contract RandomnessConsumer is Ownable, IRandomnessCallback {
    using SafeERC20 for IERC20;

    // GoatVRF contract address
    address public immutable goatVRF;

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
        if (goatVRF_ == address(0)) {
            revert("Invalid GoatVRF address");
        }

        goatVRF = goatVRF_;
    }

    /**
     * @dev Request randomness from GoatVRF
     * @param maxAllowedGasPrice Maximum allowed gas price for fulfillment
     * @return requestId Unique identifier for the request
     */
    function getNewRandom(uint256 maxAllowedGasPrice) external onlyOwner returns (uint256 requestId) {
        // Get the WGOATBTC token address from GoatVRF
        address tokenAddress = IGoatVRF(goatVRF).feeToken();

        // Gas limit for the callback function, this should be set to a reasonable value
        uint256 callbackGas = 6e5;

        // Calculate fee with sufficient gas for callback
        // The callback is simple, but we allocate extra gas to be safe
        uint256 fee = IGoatVRF(goatVRF).calculateFeeWithGasPrice(callbackGas, maxAllowedGasPrice);

        // Transfer tokens from caller to this contract if needed
        // This step is optional depending on your token handling strategy

        // Approve GoatVRF to spend tokens
        IERC20 token = IERC20(tokenAddress);
        // Since the underlying token is WGOATBTC (wrapped BTC in GOAT network), and the price is fetched from the price feed oracle in realtime,
        // we need to ensure that the contract has enough allowance for the fee. So it is better to apply a safety margin
        // to avoid any issues with gas price fluctuations. 50% is just a suggested value, you can adjust it as needed.
        // If you do not want to approve the token every time, you can also approve all of your budget at once.
        // Even if you approved the contract with a higher amount, the fee will be calculated based on
        // the gas price at the time of the request and actual usage, so you will not be charged more than the fee.
        uint256 safetyMargin = fee * 3 / 2;
        token.forceApprove(goatVRF, safetyMargin);

        // Get beacon for deadline calculation
        IDrandBeacon beacon = IDrandBeacon(IGoatVRF(goatVRF).beacon());

        // Request randomness with appropriate deadline
        uint256 deadline = block.timestamp + beacon.period();
        requestId = IGoatVRF(goatVRF).getNewRandom(deadline, maxAllowedGasPrice, callbackGas);
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
        IERC20(token_).safeTransfer(recipient, amount);
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
