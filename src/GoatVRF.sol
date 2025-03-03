// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "./interfaces/IRandomnessCallback.sol";
import "./interfaces/IDrandBeacon.sol";
import "./interfaces/IGoatVRF.sol";
import "./interfaces/IFeeRule.sol";

/**
 * @title GoatVRF
 * @dev Main contract for the GoatVRF service that provides verifiable random functions
 * Implements UUPS upgradeable pattern with OpenZeppelin libraries
 */
contract GoatVRF is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable, IGoatVRF {
    // Gas utility for exact gas forwarding
    uint256 internal constant GAS_FOR_CALL_EXACT_CHECK = 5000;

    // Storage variables
    struct GoatVRFConfig {
        // Current beacon address
        address beacon;
        // WGOATBTC token address
        address wgoatbtcToken;
        // Fee recipient address
        address feeRecipient;
        // Authorized relayer address
        address relayer;
        // Fee rule contract address
        address feeRule;
        // Maximum deadline delta (in seconds)
        uint256 maxDeadlineDelta;
        // Next request ID to be assigned
        uint256 nextRequestId;
        // Overhead gas amount to add to actual gas used
        uint256 overheadGas;
        // Request expiration time (in seconds)
        uint256 requestExpireTime;
    }

    // Main configuration
    GoatVRFConfig internal _config;

    // Mapping of request IDs to request hashes
    mapping(uint256 => bytes32) internal _requestHashes;

    // Mapping of request IDs to request states
    mapping(uint256 => RequestState) internal _requestStates;

    // Mapping of request IDs to requesters
    mapping(uint256 => address) internal _requesters;

    // Mapping of request IDs to request timestamps
    mapping(uint256 => uint256) internal _requestTimestamps;

    /**
     * @dev Modifier to restrict function access to the relayer
     */
    modifier onlyRelayer() {
        if (msg.sender != _config.relayer) {
            revert OnlyRelayer();
        }
        _;
    }

    /**
     * @dev Initializer function (replaces constructor in upgradeable contracts)
     * @param beacon_ Address of the drand beacon
     * @param wgoatbtcToken_ Address of the WGOATBTC token
     * @param feeRecipient_ Address of the fee recipient
     * @param relayer_ Address of the authorized relayer
     * @param feeRule_ Address of the fee rule contract
     * @param maxDeadlineDelta_ Maximum deadline delta in seconds
     * @param overheadGas_ Overhead gas amount
     * @param requestExpireTime_ Request expiration time in seconds
     */
    function initialize(
        address beacon_,
        address wgoatbtcToken_,
        address feeRecipient_,
        address relayer_,
        address feeRule_,
        uint256 maxDeadlineDelta_,
        uint256 overheadGas_,
        uint256 requestExpireTime_
    ) external initializer {
        // Initialize parent contracts
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Validate parameters
        if (beacon_ == address(0)) {
            revert InvalidBeacon(beacon_);
        }
        if (wgoatbtcToken_ == address(0)) {
            revert InvalidToken(wgoatbtcToken_);
        }
        if (feeRecipient_ == address(0)) {
            revert InvalidFeeRecipient(feeRecipient_);
        }
        if (relayer_ == address(0)) {
            revert InvalidRelayer(relayer_);
        }
        if (feeRule_ == address(0)) {
            revert InvalidFeeRule(feeRule_);
        }
        if (requestExpireTime_ == 0) {
            revert InvalidRequestExpireTime(requestExpireTime_);
        }

        // Set configuration
        _config.beacon = beacon_;
        _config.wgoatbtcToken = wgoatbtcToken_;
        _config.feeRecipient = feeRecipient_;
        _config.relayer = relayer_;
        _config.feeRule = feeRule_;
        _config.maxDeadlineDelta = maxDeadlineDelta_;
        _config.nextRequestId = 1;
        _config.overheadGas = overheadGas_;
        _config.requestExpireTime = requestExpireTime_;

        // Emit events
        emit ConfigUpdated("beacon", abi.encode(beacon_));
        emit ConfigUpdated("token", abi.encode(wgoatbtcToken_));
        emit ConfigUpdated("feeRecipient", abi.encode(feeRecipient_));
        emit ConfigUpdated("relayer", abi.encode(relayer_));
        emit ConfigUpdated("feeRule", abi.encode(feeRule_));
        emit ConfigUpdated("maxDeadlineDelta", abi.encode(maxDeadlineDelta_));
        emit ConfigUpdated("overheadGas", abi.encode(overheadGas_));
        emit ConfigUpdated("requestExpireTime", abi.encode(requestExpireTime_));
    }

    /**
     * @dev Get the current beacon address
     * @return beaconAddr The beacon address
     */
    function beacon() external view returns (address beaconAddr) {
        return _config.beacon;
    }

    /**
     * @dev Get the current WGOATBTC token address
     * @return tokenAddr The token address
     */
    function wgoatbtcToken() external view override returns (address tokenAddr) {
        return _config.wgoatbtcToken;
    }

    /**
     * @dev Get the current fee recipient address
     * @return recipientAddr The fee recipient address
     */
    function feeRecipient() external view returns (address recipientAddr) {
        return _config.feeRecipient;
    }

    /**
     * @dev Get the current relayer address
     * @return relayerAddr The relayer address
     */
    function relayer() external view returns (address relayerAddr) {
        return _config.relayer;
    }

    /**
     * @dev Get the current fee rule address
     * @return ruleAddr The fee rule address
     */
    function feeRule() external view returns (address ruleAddr) {
        return _config.feeRule;
    }

    /**
     * @dev Get the maximum deadline delta
     * @return maxDelta The maximum deadline delta
     */
    function maxDeadlineDelta() external view returns (uint256 maxDelta) {
        return _config.maxDeadlineDelta;
    }

    /**
     * @dev Get the next request ID
     * @return nextId The next request ID
     */
    function nextRequestId() external view returns (uint256 nextId) {
        return _config.nextRequestId;
    }

    /**
     * @dev Get the request expiration time
     * @return expireTime The request expiration time in seconds
     */
    function requestExpireTime() external view returns (uint256 expireTime) {
        return _config.requestExpireTime;
    }

    /**
     * @dev Calculate fee for a randomness request
     * @param gas Amount of gas will be using
     * @return totalFee Total fee for the request
     */
    function calculateFee(uint256 gas) external view override returns (uint256 totalFee) {
        // If gas is 0, we're calculating the fee before the request is fulfilled
        if (gas == 0) {
            return IFeeRule(_config.feeRule).calculateFee(msg.sender, 0);
        }

        // Calculate gas fee with overhead
        uint256 totalGasUsed = gas + _config.overheadGas;

        // Use the fee rule to calculate total fee
        return IFeeRule(_config.feeRule).calculateFee(msg.sender, totalGasUsed);
    }

    /**
     * @dev Calculate fee for a randomness request with custom gas price
     * @param gas Amount of gas will be using
     * @param gasPrice Custom gas price to use for calculation
     * @return totalFee Total fee for the request
     */
    function calculateFeeWithGasPrice(uint256 gas, uint256 gasPrice)
        external
        view
        override
        returns (uint256 totalFee)
    {
        // If gas is 0, we're calculating the fee before the request is fulfilled
        if (gas == 0) {
            return IFeeRule(_config.feeRule).calculateFeeWithGasPrice(msg.sender, 0, gasPrice);
        }

        // Calculate gas fee with overhead
        uint256 totalGasUsed = gas + _config.overheadGas;

        // Use the fee rule to calculate total fee with the provided gas price
        return IFeeRule(_config.feeRule).calculateFeeWithGasPrice(msg.sender, totalGasUsed, gasPrice);
    }

    /**
     * @dev Set new beacon address
     * @param beacon_ New beacon address
     */
    function setBeacon(address beacon_) external onlyOwner {
        if (beacon_ == address(0)) {
            revert InvalidBeacon(beacon_);
        }
        _config.beacon = beacon_;
        emit ConfigUpdated("beacon", abi.encode(beacon_));
    }

    /**
     * @dev Set new token address
     * @param token_ New token address
     */
    function setWgoatbtcToken(address token_) external onlyOwner {
        if (token_ == address(0)) {
            revert InvalidToken(token_);
        }
        _config.wgoatbtcToken = token_;
        emit ConfigUpdated("token", abi.encode(token_));
    }

    /**
     * @dev Set new fee recipient address
     * @param feeRecipient_ New fee recipient address
     */
    function setFeeRecipient(address feeRecipient_) external onlyOwner {
        if (feeRecipient_ == address(0)) {
            revert InvalidFeeRecipient(feeRecipient_);
        }
        _config.feeRecipient = feeRecipient_;
        emit ConfigUpdated("feeRecipient", abi.encode(feeRecipient_));
    }

    /**
     * @dev Set new relayer address
     * @param relayer_ New relayer address
     */
    function setRelayer(address relayer_) external onlyOwner {
        if (relayer_ == address(0)) {
            revert InvalidRelayer(relayer_);
        }
        _config.relayer = relayer_;
        emit ConfigUpdated("relayer", abi.encode(relayer_));
    }

    /**
     * @dev Set new fee rule contract address
     * @param feeRule_ New fee rule contract address
     */
    function setFeeRule(address feeRule_) external onlyOwner {
        if (feeRule_ == address(0)) {
            revert InvalidFeeRule(feeRule_);
        }
        _config.feeRule = feeRule_;
        emit ConfigUpdated("feeRule", abi.encode(feeRule_));
    }

    /**
     * @dev Set new maximum deadline delta
     * @param maxDeadlineDelta_ New maximum deadline delta
     */
    function setMaxDeadlineDelta(uint256 maxDeadlineDelta_) external onlyOwner {
        _config.maxDeadlineDelta = maxDeadlineDelta_;
        emit ConfigUpdated("maxDeadlineDelta", abi.encode(maxDeadlineDelta_));
    }

    /**
     * @dev Set the overhead gas amount
     * @param overheadGas_ The new overhead gas amount
     */
    function setOverheadGas(uint256 overheadGas_) external onlyOwner {
        _config.overheadGas = overheadGas_;
        emit ConfigUpdated("overheadGas", abi.encode(overheadGas_));
    }

    /**
     * @dev Set the request expiration time
     * @param requestExpireTime_ The new request expiration time in seconds
     */
    function setRequestExpireTime(uint256 requestExpireTime_) external onlyOwner {
        if (requestExpireTime_ == 0) {
            revert InvalidRequestExpireTime(requestExpireTime_);
        }
        _config.requestExpireTime = requestExpireTime_;
        emit ConfigUpdated("requestExpireTime", abi.encode(requestExpireTime_));
    }

    /**
     * @dev Get the current overhead gas amount
     * @return The overhead gas amount
     */
    function overheadGas() external view returns (uint256) {
        return _config.overheadGas;
    }

    /**
     * @dev Digest a request to create a commitment
     * @param requestId The request ID
     * @param requester The address of the requester
     * @param maxAllowedGasPrice The maximum allowed gas price
     * @param callbackGas Amount of gas allocated for the callback
     * @param round The round number of the drand beacon
     * @return requestHash The request hash
     */
    function _digestRequest(
        uint256 requestId,
        address requester,
        uint256 maxAllowedGasPrice,
        uint256 callbackGas,
        uint256 round
    ) internal view returns (bytes32 requestHash) {
        return keccak256(
            abi.encode(block.chainid, address(this), requestId, requester, maxAllowedGasPrice, callbackGas, round)
        );
    }

    /**
     * @dev Request randomness with a future deadline
     * @param deadline Timestamp after which randomness will be available
     * @param maxAllowedGasPrice Maximum allowed gas price for fulfillment
     * @param callbackGas Amount of gas allocated for the callback
     * @return requestId Unique identifier for the request
     */
    function getNewRandom(uint256 deadline, uint256 maxAllowedGasPrice, uint256 callbackGas)
        external
        override
        nonReentrant
        returns (uint256 requestId)
    {
        // Get beacon information
        IDrandBeacon drandBeacon = IDrandBeacon(_config.beacon);
        uint256 genesis = drandBeacon.genesisTimestamp();
        uint256 period = drandBeacon.period();

        // Validate deadline
        if (
            (deadline > block.timestamp + _config.maxDeadlineDelta) || (deadline < genesis)
                || deadline < (block.timestamp + period)
        ) {
            revert InvalidDeadline(deadline);
        }

        // Calculate round from deadline
        uint256 delta = deadline - genesis;
        uint256 round = (delta / period) + ((delta % period > 0) ? 1 : 0);

        // Validate max allowed gas price
        if (maxAllowedGasPrice == 0) {
            revert InvalidGasPrice(maxAllowedGasPrice);
        }

        // Calculate the fixed fee for the request
        uint256 intrinsicFee = IFeeRule(_config.feeRule).calculateFee(msg.sender, 0);

        // Check user's allowance and balance for the fixed fee
        IERC20 token = IERC20(_config.wgoatbtcToken);
        uint256 allowance = token.allowance(msg.sender, address(this));
        uint256 balance = token.balanceOf(msg.sender);

        if (allowance < intrinsicFee) {
            revert InsufficientAllowance(allowance, intrinsicFee);
        }

        if (balance < intrinsicFee) {
            revert InsufficientBalance(balance, intrinsicFee);
        }

        // Get request ID
        requestId = _config.nextRequestId++;

        // Store digested request
        bytes32 requestHash = _digestRequest(requestId, msg.sender, maxAllowedGasPrice, callbackGas, round);

        _requestHashes[requestId] = requestHash;
        _requestStates[requestId] = RequestState.Pending;
        _requesters[requestId] = msg.sender;
        _requestTimestamps[requestId] = block.timestamp;

        // Emit event
        emit NewRequest(requestId, msg.sender, maxAllowedGasPrice, callbackGas, round);

        return requestId;
    }

    /**
     * @dev Fulfill a randomness request
     * @param requestId The ID of the request to fulfill
     * @param requester The address that made the request
     * @param maxAllowedGasPrice The maximum allowed gas price
     * @param callbackGas Amount of gas allocated for the callback
     * @param round The round number for verification
     * @param signature The signature from the drand beacon
     */
    function fulfillRequest(
        uint256 requestId,
        address requester,
        uint256 maxAllowedGasPrice,
        uint256 callbackGas,
        uint256 round,
        bytes calldata signature
    ) external onlyRelayer nonReentrant {
        // Validate request state
        if (_requestStates[requestId] != RequestState.Pending) {
            revert RequestNotPending(requestId);
        }

        // Check if request has expired
        if (block.timestamp > _requestTimestamps[requestId] + _config.requestExpireTime) {
            revert RequestExpired(_config.requestExpireTime);
        }

        // Check gas price
        if (tx.gasprice > maxAllowedGasPrice) {
            revert InvalidGasPrice(tx.gasprice);
        }

        // Verify request hash
        bytes32 requestHash = _digestRequest(requestId, requester, maxAllowedGasPrice, callbackGas, round);

        if (_requestHashes[requestId] != requestHash) {
            revert InvalidRequestHash(requestHash);
        }

        // Verify the beacon signature - will revert if invalid
        IDrandBeacon(_config.beacon).verifyBeaconRound(round, signature);

        // Generate randomness using signature and request data
        uint256 randomness =
            uint256(keccak256(abi.encode(keccak256(signature), block.chainid, address(this), requestId, requester)));

        // Mark request as fulfilled
        _requestStates[requestId] = RequestState.Fulfilled;

        // Prepare callback
        IRandomnessCallback callback = IRandomnessCallback(requester);

        uint256 remainingGas = gasleft();
        uint256 requiredGas = callbackGas + GAS_FOR_CALL_EXACT_CHECK;
        if (remainingGas < callbackGas + GAS_FOR_CALL_EXACT_CHECK) {
            revert InsufficientGasForCallback(requiredGas, remainingGas);
        }

        // Call the callback with remaining gas
        bool success = _callWithExactGas(
            requiredGas,
            address(callback),
            abi.encodeWithSelector(callback.receiveRandomness.selector, requestId, randomness)
        );

        // Update request state if callback failed
        if (!success) {
            _requestStates[requestId] = RequestState.Failed;
        }

        uint256 totalFee = _processPayment(requester, requiredGas);

        // Emit fulfillment event
        emit RequestFulfilled(requestId, randomness, success, totalFee);
    }

    /**
     * @dev Cancel a pending randomness request
     * @param requestId Unique identifier for the request to cancel
     */
    function cancelRequest(uint256 requestId) external override {
        // Check request state
        if (_requestStates[requestId] != RequestState.Pending) {
            revert RequestNotPending(requestId);
        }

        // Verify caller is the requester only
        if (msg.sender != _requesters[requestId]) {
            revert InvalidUser(msg.sender);
        }

        // Update request state
        _requestStates[requestId] = RequestState.Cancelled;

        // Emit cancellation event
        emit RequestCanceled(requestId, _requesters[requestId]);
    }

    /**
     * @dev Process payment for a request
     * @param requester The requester address
     * @param gasUsed The amount of gas used
     * @return totalFee The total fee charged
     */
    function _processPayment(address requester, uint256 gasUsed) internal returns (uint256 totalFee) {
        // Add overhead gas to the actual gas used
        uint256 totalGasUsed = gasUsed + _config.overheadGas;

        // Calculate fee using fee rule
        totalFee = IFeeRule(_config.feeRule).calculateFee(requester, totalGasUsed);

        IERC20 token = IERC20(_config.wgoatbtcToken);

        // Get current allowance
        uint256 allowance = token.allowance(requester, address(this));
        uint256 balance = token.balanceOf(requester);

        // User must have enough allowance and balance to cover fee
        if (allowance < totalFee) {
            revert InsufficientAllowance(allowance, totalFee);
        }

        if (balance < totalFee) {
            revert InsufficientBalance(balance, totalFee);
        }

        // Transfer tokens
        bool success = token.transferFrom(requester, _config.feeRecipient, totalFee);
        if (!success) {
            revert PaymentProcessingFailed(0, "Transfer failed");
        }

        return totalFee;
    }

    /**
     * @dev Get the request timestamp
     * @param requestId Unique identifier for the request
     * @return timestamp Timestamp when the request was created
     */
    function getRequestTimestamp(uint256 requestId) external view returns (uint256 timestamp) {
        return _requestTimestamps[requestId];
    }

    /**
     * @dev Get the state of a randomness request
     * @param requestId Unique identifier for the request
     * @return state Current state of the request
     */
    function getRequestState(uint256 requestId) external view override returns (RequestState state) {
        state = _requestStates[requestId];
        if (state == RequestState.Pending) {
            if (block.timestamp > _requestTimestamps[requestId] + _config.requestExpireTime) {
                state = RequestState.Cancelled;
            }
        }

        return state;
    }

    /**
     * @dev Get details of a randomness request
     * @param requestId Unique identifier for the request
     * @return requester Address that made the request
     * @return state Current state of the request
     */
    function getRequestDetails(uint256 requestId) external view returns (address requester, RequestState state) {
        return (_requesters[requestId], _requestStates[requestId]);
    }

    /**
     * @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract.
     * Called by {upgradeTo} and {upgradeToAndCall}.
     * @param newImplementation address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * @dev Call a function with exact gas
     * @param gasAmount Amount of gas to forward
     * @param target Address to call
     * @param data Call data
     * @return success Whether the call succeeded
     */
    function _callWithExactGas(uint256 gasAmount, address target, bytes memory data) private returns (bool success) {
        // Call with exact gas
        assembly {
            // Call with all but GAS_FOR_CALL_EXACT_CHECK gas
            success :=
                call(
                    gasAmount, // gas
                    target, // recipient
                    0, // ether value
                    add(data, 32), // input data pointer
                    mload(data), // input data length
                    0, // output area pointer
                    0 // output area length
                )
        }

        return success;
    }
}
