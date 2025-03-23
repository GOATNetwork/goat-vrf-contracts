// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IRandomnessCallback.sol";
import "./interfaces/IDrandBeacon.sol";
import "./interfaces/IGoatVRF.sol";
import "./interfaces/IFeeRule.sol";

/**
 * @title GoatVRF
 * @dev Main contract for the GoatVRF service that provides verifiable random functions.
 * Implements UUPS upgradeable pattern with OpenZeppelin libraries.
 */
contract GoatVRF is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable, IGoatVRF {
    using SafeERC20 for IERC20;

    /**
     * @dev This constant represents the gas buffer used in the _callWithExactGas method.
     * We subtract it from the parent's remaining gas to ensure we still have enough gas
     * for safety checks and potential reverts after the call.
     */
    uint256 internal constant GAS_FOR_CALL_EXACT_CHECK = 5000;

    // Immutable variables
    uint256 internal immutable OVERHEAD_GAS;
    // Maximum deadline delta in seconds, e.g. if set to 7 days, the user can request randomness
    // up to 7 days in the future.
    uint256 internal immutable MAX_DEADLINE_DELTA;
    // Request expiration time in seconds, e.g. if set to 7 days, the request will be considered
    // expired if not fulfilled within 7 days.
    uint256 internal immutable REQUEST_EXPIRE_TIME;
    // Maximum callback gas allowed
    uint256 internal immutable MAX_CALLBACK_GAS;
    // ERC20 token address for fee payment
    address internal immutable FEE_TOKEN;

    struct GoatVRFConfig {
        // Current beacon address
        address beacon;
        // Fee recipient address
        address feeRecipient;
        // Authorized relayer address
        address relayer;
        // Fee rule contract address
        address feeRule;
        // Next request ID to be assigned
        uint256 nextRequestId;
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
     * @dev Constructor func
     * @param feeToken_ Address of the ERC20 token to pay the fee
     * @param maxDeadlineDelta_ Maximum deadline delta in seconds
     * @param overheadGas_ Overhead gas amount
     * @param requestExpireTime_ Request expiration time in seconds
     * @param maxCallbackGas_ Maximum callback gas allowed
     */
    constructor(
        address feeToken_,
        uint256 maxDeadlineDelta_,
        uint256 overheadGas_,
        uint256 requestExpireTime_,
        uint256 maxCallbackGas_
    ) {
        if (feeToken_ == address(0)) {
            revert InvalidToken(feeToken_);
        }
        if (requestExpireTime_ == 0) {
            revert InvalidRequestExpireTime(requestExpireTime_);
        }
        if (maxCallbackGas_ == 0) {
            revert InvalidCallbackGas(maxCallbackGas_);
        }
        if (maxDeadlineDelta_ == 0) {
            revert InvalidDeadline(maxDeadlineDelta_);
        }

        MAX_CALLBACK_GAS = maxCallbackGas_;
        OVERHEAD_GAS = overheadGas_;
        MAX_DEADLINE_DELTA = maxDeadlineDelta_;
        REQUEST_EXPIRE_TIME = requestExpireTime_;
        FEE_TOKEN = feeToken_;

        _disableInitializers();
    }

    /**
     * @dev Initializer function (replaces constructor in upgradeable contracts).
     *      *IMPORTANT*: For production, set the 'owner' to a multisig or timelock to reduce centralization risk.
     *
     * @param beacon_ Address of the drand beacon
     * @param feeRecipient_ Address of the fee recipient
     * @param relayer_ Address of the authorized relayer
     * @param feeRule_ Address of the fee rule contract
     */
    function initialize(address beacon_, address feeRecipient_, address relayer_, address feeRule_)
        external
        initializer
    {
        // Initialize parent contracts
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        // Validate parameters
        if (beacon_ == address(0)) {
            revert InvalidBeacon(beacon_);
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

        // Set configuration
        _config.beacon = beacon_;
        _config.feeRecipient = feeRecipient_;
        _config.relayer = relayer_;
        _config.feeRule = feeRule_;
        _config.nextRequestId = 1;

        // Emit events
        emit ConfigUpdated("beacon", abi.encode(beacon_));
        emit ConfigUpdated("feeRecipient", abi.encode(feeRecipient_));
        emit ConfigUpdated("relayer", abi.encode(relayer_));
        emit ConfigUpdated("feeRule", abi.encode(feeRule_));
    }

    /**
     * @dev Get the current beacon address
     * @return beaconAddr The beacon address
     */
    function beacon() external view returns (address beaconAddr) {
        return _config.beacon;
    }

    /**
     * @dev Get the current fee token address
     * @return tokenAddr The token address
     */
    function feeToken() external view override returns (address tokenAddr) {
        return FEE_TOKEN;
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
        return MAX_DEADLINE_DELTA;
    }

    /**
     * @dev Get the maximum callback gas amount
     * @return callbackGas The maximum callback gas amount
     */
    function maxCallbackGas() external view returns (uint256 callbackGas) {
        return MAX_CALLBACK_GAS;
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
        return REQUEST_EXPIRE_TIME;
    }

    /**
     * @dev Calculate fee for a randomness request
     * @param gas Amount of gas will be using
     * @return totalFee Total fee for the request
     *
     * Note: This function uses msg.sender to identify the requester. For auditing
     * reasons, consider having an explicit parameter if you need to calculate fees
     * for another address.
     */
    function calculateFee(uint256 gas) external view override returns (uint256 totalFee) {
        return calculateFee(msg.sender, gas);
    }

    /**
     * @dev Calculate fee for a randomness request
     * @param addr Address of the requester
     * @param gas Amount of gas will be using
     * @return totalFee Total fee for the request
     *
     * Note: This function uses msg.sender to identify the requester. For auditing
     * reasons, consider having an explicit parameter if you need to calculate fees
     * for another address.
     */
    function calculateFee(address addr, uint256 gas) public view override returns (uint256 totalFee) {
        // If gas is 0, we're calculating the fee before the request is fulfilled
        if (gas == 0) {
            return IFeeRule(_config.feeRule).calculateFee(addr, 0);
        }

        // Calculate gas fee with overhead
        uint256 totalGasUsed = gas + OVERHEAD_GAS;

        // Use the fee rule to calculate total fee
        return IFeeRule(_config.feeRule).calculateFee(addr, totalGasUsed);
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
        return calculateFeeWithGasPrice(msg.sender, gas, gasPrice);
    }

    /**
     * @dev Calculate fee for a randomness request with custom gas price
     * @param addr Address of the requester
     * @param gas Amount of gas will be using
     * @param gasPrice Custom gas price to use for calculation
     * @return totalFee Total fee for the request
     */
    function calculateFeeWithGasPrice(address addr, uint256 gas, uint256 gasPrice)
        public
        view
        override
        returns (uint256 totalFee)
    {
        // If gas is 0, we're calculating the fee before the request is fulfilled
        if (gas == 0) {
            return IFeeRule(_config.feeRule).calculateFeeWithGasPrice(addr, 0, gasPrice);
        }

        // Calculate gas fee with overhead
        uint256 totalGasUsed = gas + OVERHEAD_GAS;

        // Use the fee rule to calculate total fee with the provided gas price
        return IFeeRule(_config.feeRule).calculateFeeWithGasPrice(addr, totalGasUsed, gasPrice);
    }

    /**
     * @dev Set new beacon address
     * @param beacon_ New beacon address
     *
     * For decentralized usage, the owner should be a timelock or multi-signature address.
     */
    function setBeacon(address beacon_) external onlyOwner {
        if (beacon_ == address(0)) {
            revert InvalidBeacon(beacon_);
        }
        _config.beacon = beacon_;
        emit ConfigUpdated("beacon", abi.encode(beacon_));
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
     * @dev Get the current overhead gas amount
     * @return The overhead gas amount
     */
    function overheadGas() external view returns (uint256) {
        return OVERHEAD_GAS;
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
        uint256 round,
        address beaconAddr,
        address feeRuleAddr
    ) internal view returns (bytes32 requestHash) {
        return keccak256(
            abi.encode(
                block.chainid,
                address(this),
                requestId,
                requester,
                maxAllowedGasPrice,
                callbackGas,
                round,
                beaconAddr,
                feeRuleAddr
            )
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
        // Validate callback gas
        if (callbackGas > MAX_CALLBACK_GAS || callbackGas == 0) {
            revert InvalidCallbackGas(callbackGas);
        }

        // Validate max allowed gas price
        if (maxAllowedGasPrice == 0) {
            revert InvalidGasPrice(maxAllowedGasPrice);
        }

        // Get beacon information
        IDrandBeacon drandBeacon = IDrandBeacon(_config.beacon);
        uint256 genesis = drandBeacon.genesisTimestamp();
        uint256 period = drandBeacon.period();

        // Validate deadline
        if (
            (deadline > block.timestamp + MAX_DEADLINE_DELTA) || (deadline < genesis)
                || (deadline < (block.timestamp + period))
        ) {
            revert InvalidDeadline(deadline);
        }

        // Calculate round from deadline
        uint256 delta = deadline - genesis;
        uint256 round = (delta / period) + ((delta % period > 0) ? 1 : 0);

        // Calculate the fixed fee for the request (for pre-check only)
        uint256 intrinsicFee = calculateFeeWithGasPrice(msg.sender, callbackGas, maxAllowedGasPrice);

        // Check user's allowance and balance for that fixed fee
        IERC20 token = IERC20(FEE_TOKEN);
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
        address beaconAddr = _config.beacon;
        address feeRuleAddr = _config.feeRule;

        // Store digested request
        bytes32 requestHash =
            _digestRequest(requestId, msg.sender, maxAllowedGasPrice, callbackGas, round, beaconAddr, feeRuleAddr);
        _requestHashes[requestId] = requestHash;
        _requestStates[requestId] = RequestState.Pending;
        _requesters[requestId] = msg.sender;
        _requestTimestamps[requestId] = deadline;

        // Emit event
        emit NewRequest(requestId, msg.sender, beaconAddr, feeRuleAddr, maxAllowedGasPrice, callbackGas, round);

        return requestId;
    }

    /**
     * @dev Fulfill a randomness request
     * @param requestId The ID of the request to fulfill
     * @param requester The address that made the request
     * @param maxAllowedGasPrice The maximum allowed gas price
     * @param callbackGas Amount of gas allocated for the callback
     * @param round The round number for verification
     * @param beaconAddr The address of the drand beacon
     * @param feeRuleAddr The address of the fee rule contract
     * @param signature The signature from the drand beacon
     */
    function fulfillRequest(
        uint256 requestId,
        address requester,
        uint256 maxAllowedGasPrice,
        uint256 callbackGas,
        uint256 round,
        address beaconAddr,
        address feeRuleAddr,
        bytes calldata signature
    ) external nonReentrant onlyRelayer {
        if (beaconAddr == address(0)) {
            revert InvalidBeacon(beaconAddr);
        }

        // Validate request state
        if (_requestStates[requestId] != RequestState.Pending) {
            revert RequestNotPending(requestId);
        }

        // Check if request has expired
        if (block.timestamp > _requestTimestamps[requestId] + REQUEST_EXPIRE_TIME) {
            revert RequestExpired(REQUEST_EXPIRE_TIME);
        }

        // Check gas price
        if (tx.gasprice > maxAllowedGasPrice) {
            revert InvalidGasPrice(tx.gasprice);
        }

        // Verify request hash
        bytes32 requestHash =
            _digestRequest(requestId, requester, maxAllowedGasPrice, callbackGas, round, beaconAddr, feeRuleAddr);
        if (_requestHashes[requestId] != requestHash) {
            revert InvalidRequestHash(requestHash);
        }

        // Verify the beacon signature - will revert if invalid
        IDrandBeacon(beaconAddr).verifyBeaconRound(round, signature);

        // Generate randomness using signature and request data
        uint256 randomness =
            uint256(keccak256(abi.encode(keccak256(signature), block.chainid, address(this), requestId, requester)));

        // Mark request as fulfilled (tentatively)
        _requestStates[requestId] = RequestState.Fulfilled;

        // Prepare callback
        IRandomnessCallback callbackContract = IRandomnessCallback(requester);

        // We do a precise gas check approach
        uint256 startGas = gasleft();
        uint256 requiredGas = callbackGas + GAS_FOR_CALL_EXACT_CHECK;

        if (startGas < requiredGas) {
            revert InsufficientGasForCallback(requiredGas, startGas);
        }

        // Call the callback with exact gas
        bool success = _callWithExactGas(
            requiredGas,
            requester,
            abi.encodeWithSelector(callbackContract.receiveRandomness.selector, requestId, randomness)
        );
        uint256 gasUsed = startGas - gasleft();

        if (!success) {
            // If callback fails, mark as Failed
            _requestStates[requestId] = RequestState.Failed;
            emit CallbackFailed(requestId, requester);
        }

        // Process the payment
        uint256 totalFee = _processPayment(requester, gasUsed, feeRuleAddr);

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
     * @param gasUsed The amount of gas used (callbackGas + buffer in minimal fix)
     * @param feeRuleAddr The fee rule contract address
     * @return totalFee The total fee charged
     */
    function _processPayment(address requester, uint256 gasUsed, address feeRuleAddr)
        internal
        returns (uint256 totalFee)
    {
        // Add overhead gas to the user-specified gas usage
        uint256 totalGasUsed = gasUsed + OVERHEAD_GAS;

        // Calculate fee using fee rule
        totalFee = IFeeRule(feeRuleAddr).calculateFee(requester, totalGasUsed);

        // Transfer tokens (basic check for success)
        IERC20(FEE_TOKEN).safeTransferFrom(requester, _config.feeRecipient, totalFee);
        return totalFee;
    }

    /**
     * @dev Get the request timestamp
     * @param requestId Unique identifier for the request
     * @return timestamp Timestamp when the request will be executed
     */
    function getRequestTimestamp(uint256 requestId) external view returns (uint256 timestamp) {
        return _requestTimestamps[requestId];
    }

    /**
     * @dev Get the state of a randomness request
     * @param requestId Unique identifier for the request
     * @return state Current state of the request
     *
     * If the request is pending and the current time has exceeded requestExpireTime,
     * we return Expired instead of Cancelled (which was a misleading outcome).
     */
    function getRequestState(uint256 requestId) external view override returns (RequestState state) {
        state = _requestStates[requestId];
        if (state == RequestState.Pending) {
            // Check for expiration
            if (block.timestamp > _requestTimestamps[requestId] + REQUEST_EXPIRE_TIME) {
                state = RequestState.Expired;
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
     * @dev Call a function with exact gas, ensuring that if the parent contract cannot
     * provide enough gas (due to EIP-150's 63/64 rule), it will revert rather than
     * silently passing less gas to the callee.
     *
     * @param gasAmount Amount of gas to forward (expected to be exact, including a small buffer)
     * @param target Address to call
     * @param data Call data
     * @return success Whether the call succeeded
     */
    function _callWithExactGas(uint256 gasAmount, address target, bytes memory data) private returns (bool success) {
        assembly {
            // Read the current gas left
            let g := gas()

            // If we don't have enough gas to handle the post-check logic, revert
            if lt(g, GAS_FOR_CALL_EXACT_CHECK) {
                let ptr := mload(0x40)
                mstore(ptr, 0x4E6F2047617320466F722043616C6C20457861637420436865636B000000)
                // "No gas for call exact check"
                revert(ptr, 0x20)
            }

            // Subtract the buffer from total available gas
            g := sub(g, GAS_FOR_CALL_EXACT_CHECK)

            // After EIP-150, actual gas for call is ~ (g - g//64).
            // If (g - g//64) < gasAmount, revert to avoid partial gas forward.
            if iszero(gt(sub(g, div(g, 64)), gasAmount)) {
                let ptr := mload(0x40)
                mstore(ptr, 0x4E6F7420656E6F7567682067617320666F722063616C6C00000000000000)
                // "Not enough gas for call"
                revert(ptr, 0x1C)
            }

            // Perform the call with the specified gasAmount
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
