// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IGoatVRF
 * @dev Interface for the GoatVRF contract
 */
interface IGoatVRF {
    // Error definitions
    error InvalidDeadline(uint256 deadline);
    error InvalidUser(address user);
    error InvalidGasPrice(uint256 gasPrice);
    error RequestExpired(uint256 expireTime);
    error InvalidBeacon(address beacon);
    error InvalidToken(address token);
    error InvalidFeeRecipient(address recipient);
    error InvalidRelayer(address relayer);
    error InvalidFeeRule(address feeRule);
    error InvalidMaxDeadlineDelta(uint256 maxDeadlineDelta);
    error InvalidRequestExpireTime(uint256 expireTime);
    error OnlyRelayer();
    error RequestNotPending(uint256 requestId);
    error PaymentProcessingFailed(uint256 requestId, string reason);
    error InsufficientAllowance(uint256 allowance, uint256 required);
    error InsufficientBalance(uint256 balance, uint256 required);
    error InvalidRequestHash(bytes32 requestHash);
    error InsufficientGasForCallback(uint256 requiredGas, uint256 remainingGas);
    error InvalidCallbackGas(uint256 callbackGas);

    /**
     * @dev Emitted when any configuration is updated
     * @param name The name of the configuration parameter
     * @param value The new value (address or uint256 encoded as bytes)
     */
    event ConfigUpdated(string name, bytes value);

    /**
     * @dev Emitted when randomness is requested
     * @param requestId Unique identifier for the request
     * @param requester Address that made the request
     * @param maxAllowedGasPrice Maximum allowed gas price for fulfillment
     * @param callbackGas Amount of gas allocated for the callback
     * @param round Round number for the request
     */
    event NewRequest(
        uint256 indexed requestId,
        address indexed requester,
        uint256 maxAllowedGasPrice,
        uint256 callbackGas,
        uint256 round
    );

    /**
     * @dev Emitted when a randomness request is cancelled
     * @param requestId Unique identifier for the request
     * @param requester Address that made the request
     */
    event RequestCanceled(uint256 indexed requestId, address indexed requester);

    /**
     * @dev Emitted when randomness is fulfilled
     * @param requestId Unique identifier for the request
     * @param randomness The randomness value
     * @param success Whether the callback succeeded
     * @param totalFee Total fee charged for the request
     */
    event RequestFulfilled(uint256 indexed requestId, uint256 randomness, bool success, uint256 totalFee);

    /**
     * @dev Emitted when a callback fails
     * @param requestId Unique identifier for the request
     * @param callbackContract Address of the contract that failed to fulfill the request
     */
    event CallbackFailed(uint256 indexed requestId, address indexed callbackContract);

    /**
     * @dev Enum representing the state of a randomness request
     */
    enum RequestState {
        None, // Request does not exist
        Pending, // Request is pending fulfillment
        Fulfilled, // Request has been fulfilled
        Failed, // Request fulfillment failed
        Cancelled, // Request was cancelled
        Expired // Request has expired

    }

    /**
     * @dev Struct representing a pending request
     */
    struct PendingRequest {
        uint256 requestId;
        uint256 deadline;
    }

    /**
     * @dev Calculate the fee for a randomness request
     * @param gas Amount of gas will be using
     * @return totalFee Total fee for the request
     */
    function calculateFee(uint256 gas) external view returns (uint256 totalFee);

    /**
     * @dev Calculate the fee for a randomness request
     * @param addr Address of the requester
     * @param gas Amount of gas will be using
     * @return totalFee Total fee for the request
     */
    function calculateFee(address addr, uint256 gas) external view returns (uint256 totalFee);

    /**
     * @dev Calculate the fee for a randomness request with custom gas price
     * @param gas Amount of gas will be using
     * @param gasPrice Custom gas price to use for calculation
     * @return totalFee Total fee for the request
     */
    function calculateFeeWithGasPrice(uint256 gas, uint256 gasPrice) external view returns (uint256 totalFee);

    /**
     * @dev Calculate the fee for a randomness request with custom gas price
     * @param addr Address of the requester
     * @param gas Amount of gas will be using
     * @param gasPrice Custom gas price to use for calculation
     * @return totalFee Total fee for the request
     */
    function calculateFeeWithGasPrice(address addr, uint256 gas, uint256 gasPrice)
        external
        view
        returns (uint256 totalFee);

    /**
     * @dev Request randomness with a future deadline
     * @param deadline Timestamp after which randomness will be available
     * @param maxAllowedGasPrice Maximum allowed gas price for fulfillment
     * @param callbackGas Amount of gas allocated for the callback
     * @return requestId Unique identifier for the request
     */
    function getNewRandom(uint256 deadline, uint256 maxAllowedGasPrice, uint256 callbackGas)
        external
        returns (uint256 requestId);

    /**
     * @dev Cancel a pending randomness request
     * @param requestId Unique identifier for the request to cancel
     */
    function cancelRequest(uint256 requestId) external;

    /**
     * @dev Get the current beacon address
     * @return beaconAddr The beacon address
     */
    function beacon() external view returns (address beaconAddr);

    /**
     * @dev Get the current erc20 fee token address
     * @return tokenAddr The token address
     */
    function feeToken() external view returns (address tokenAddr);

    /**
     * @dev Get the state of a randomness request
     * @param requestId Unique identifier for the request
     * @return state Current state of the request
     */
    function getRequestState(uint256 requestId) external view returns (RequestState state);

    /**
     * @dev Get the current max deadline delta
     * @return The max deadline delta
     */
    function maxDeadlineDelta() external view returns (uint256);

    /**
     * @dev Get the overhead gas amount
     * @return The overhead gas amount
     */
    function overheadGas() external view returns (uint256);

    /**
     * @dev Get the current fee rule address
     * @return The fee rule address
     */
    function feeRule() external view returns (address);

    /**
     * @dev Get the request expiration time
     * @return The request expiration time in seconds
     */
    function requestExpireTime() external view returns (uint256);

    /**
     * @dev Get the request timestamp
     * @param requestId Unique identifier for the request
     * @return The timestamp when the request was created
     */
    function getRequestTimestamp(uint256 requestId) external view returns (uint256);
}
