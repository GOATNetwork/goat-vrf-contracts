// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {CommonBase} from "../lib/forge-std/src/Base.sol";
import {StdAssertions} from "../lib/forge-std/src/StdAssertions.sol";
import {StdChains} from "../lib/forge-std/src/StdChains.sol";
import {StdCheats, StdCheatsSafe} from "../lib/forge-std/src/StdCheats.sol";
import {StdUtils} from "../lib/forge-std/src/StdUtils.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {GoatVRF} from "../src/GoatVRF.sol";
import {IDrandBeacon} from "../src/interfaces/IDrandBeacon.sol";
import {IFeeRule} from "../src/interfaces/IFeeRule.sol";
import {IGoatVRF} from "../src/interfaces/IGoatVRF.sol";
import {IRandomnessCallback} from "../src/interfaces/IRandomnessCallback.sol";
import {MockDrandBeacon, MockFeeRule} from "./GoatVRF.t.sol";
import {Test, console2} from "forge-std/Test.sol";
import {IERC20, ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockWGOATBTC
 * @dev Mock implementation of IERC20 for testing
 */
contract MockWGOATBTC is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function allowance(address owner, address spender) external view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        _balances[msg.sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        require(_allowances[sender][msg.sender] >= amount, "ERC20: transfer amount exceeds allowance");
        _allowances[sender][msg.sender] -= amount;
        _balances[sender] -= amount;
        _balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    // Mint function for testing
    function mint(address account, uint256 amount) external {
        _balances[account] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), account, amount);
    }
}

/**
 * @title MockFeeRule
 * @dev Mock implementation of IFeeRule for testing
 */
contract MockFeeRule is IFeeRule {
    uint256 private _fixedFee;

    constructor(uint256 fixedFee_) {
        _fixedFee = fixedFee_;
    }

    function calculateFee(address, uint256 gasUsed) external view override returns (uint256) {
        if (gasUsed == 0) {
            return _fixedFee;
        }

        uint256 gasFee = gasUsed * tx.gasprice;
        return _fixedFee + gasFee;
    }

    function calculateFeeWithGasPrice(address, uint256 gasUsed, uint256 gasPrice)
        external
        view
        override
        returns (uint256)
    {
        if (gasUsed == 0) {
            return _fixedFee;
        }

        uint256 gasFee = gasUsed * gasPrice;
        return _fixedFee + gasFee;
    }

    function fixedFee() external view returns (uint256) {
        return _fixedFee;
    }

    function setFixedFee(uint256 fixedFee_) external {
        _fixedFee = fixedFee_;
    }
}

/**
 * @title MockCallback
 * @dev Mock implementation of IRandomnessCallback for testing
 */
contract MockCallback is IRandomnessCallback {
    uint256 public lastRequestId;
    uint256 public lastRandomness;
    bool public shouldRevert;

    function receiveRandomness(uint256 requestId, uint256 randomness) external override {
        lastRequestId = requestId;
        lastRandomness = randomness;

        if (shouldRevert) {
            revert("Callback reverted");
        }
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
}

/**
 * @title MockDrandBeacon
 * @dev Mock implementation of IDrandBeacon for testing
 */
contract MockDrandBeacon is IDrandBeacon {
    uint256 private _genesisTimestamp;
    uint256 private _period;
    bytes private _publicKey;
    bytes32 private _publicKeyHash;

    constructor() {
        _genesisTimestamp = block.timestamp;
        _period = 30; // 30 seconds period
        _publicKey =
            hex"868f005eb8e6e4ca0a47c8a77ceaa5309a47978a7c71bc5cce96366b5d7a569937c529eeda66c7293784a9402801af31"; // Test public key
        _publicKeyHash = keccak256(_publicKey);
    }

    function verifyBeaconRound(uint256 round, bytes calldata signature) external view override {
        // Mock implementation always verifies successfully
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

/**
 * @title MockRandomnessConsumer
 * @dev Mock consumer for testing randomness callbacks
 */
contract MockRandomnessConsumer is IRandomnessCallback {
    // GoatVRF contract address
    address public goatVRF;

    // Random number storage
    mapping(uint256 => uint256) public randomResults;

    // Events
    event RandomnessReceived(uint256 indexed requestId, uint256 randomness);

    // Keep track of whether the callback was successful
    bool public callbackSucceeded;

    /**
     * @dev Constructor
     * @param goatVRF_ Address of the GoatVRF contract
     */
    constructor(address goatVRF_) {
        goatVRF = goatVRF_;
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
        callbackSucceeded = true;

        // Emit event
        emit RandomnessReceived(requestId, randomness);
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

/**
 * @title MockFailingConsumer
 * @dev Mock consumer that intentionally fails during callback for testing
 */
contract MockFailingConsumer is IRandomnessCallback {
    // GoatVRF contract address
    address public goatVRF;

    /**
     * @dev Constructor
     * @param goatVRF_ Address of the GoatVRF contract
     */
    constructor(address goatVRF_) {
        goatVRF = goatVRF_;
    }

    /**
     * @dev Callback function that always reverts
     */
    function receiveRandomness(uint256, uint256) external view override {
        // Only GoatVRF can call this function
        require(msg.sender == goatVRF, "Only GoatVRF can fulfill randomness");

        // Always revert to simulate a failing callback
        revert("Callback intentionally failed");
    }
}

/**
 * @title MockAdvancedConsumer
 * @dev Mock consumer with advanced randomness usage for testing
 */
contract MockAdvancedConsumer is IRandomnessCallback {
    // GoatVRF contract address
    address public goatVRF;

    // Random number storage
    mapping(uint256 => uint256) public randomResults;

    // Derived values from randomness
    mapping(uint256 => uint256[]) public derivedValues;

    // Events
    event RandomnessReceived(uint256 indexed requestId, uint256 randomness);
    event DerivedValuesGenerated(uint256 indexed requestId, uint256[] values);

    // Keep track of callback statistics
    bool public callbackSucceeded;
    uint256 public lastGasUsed;

    /**
     * @dev Constructor
     * @param goatVRF_ Address of the GoatVRF contract
     */
    constructor(address goatVRF_) {
        goatVRF = goatVRF_;
    }

    /**
     * @dev Advanced callback function that performs complex computations
     * @param requestId Unique identifier for the randomness request
     * @param randomness The random value
     */
    function receiveRandomness(uint256 requestId, uint256 randomness) external override {
        // Start measuring gas
        uint256 startGas = gasleft();

        // Only GoatVRF can call this function
        require(msg.sender == goatVRF, "Only GoatVRF can fulfill randomness");

        // Store the original randomness
        randomResults[requestId] = randomness;

        // Generate 5 derived random values using different offsets
        uint256[] memory values = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            values[i] = uint256(keccak256(abi.encode(randomness, i)));
        }

        // Store the derived values
        derivedValues[requestId] = values;

        // Emit events
        emit RandomnessReceived(requestId, randomness);
        emit DerivedValuesGenerated(requestId, values);

        // Mark callback as successful
        callbackSucceeded = true;

        // Calculate gas used
        lastGasUsed = startGas - gasleft();
    }

    /**
     * @dev Get derived values from a specific request
     * @param requestId Unique identifier for the randomness request
     * @return Array of derived values
     */
    function getDerivedValues(uint256 requestId) external view returns (uint256[] memory) {
        return derivedValues[requestId];
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

/**
 * @title GoatVRFTest
 * @dev Test contract for GoatVRF
 */
contract GoatVRFTest is Test {
    GoatVRF public goatVRF;
    MockDrandBeacon public mockBeacon;
    MockCallback public callback;
    MockWGOATBTC public token;
    MockFeeRule public feeRule;

    address public owner = address(1);
    address public relayer = address(2);
    address public feeRecipient = address(3);
    address public user = address(4);

    uint256 public constant FIXED_FEE = 1 ether;
    uint256 public constant OVERHEAD_GAS = 50000;
    uint256 public constant MAX_DEADLINE_DELTA = 7 days;
    uint256 public constant REQUEST_EXPIRE_TIME = 7 days;

    event RandomnessRequested(
        uint256 indexed requestId,
        address indexed requester,
        uint256 maxAllowedGasPrice,
        uint256 callbackGas,
        uint256 round
    );

    event ConfigUpdated(string name, bytes value);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        mockBeacon = new MockDrandBeacon();
        callback = new MockCallback();
        token = new MockWGOATBTC();
        feeRule = new MockFeeRule(FIXED_FEE);

        // Deploy GoatVRF
        goatVRF = new GoatVRF();
        goatVRF.initialize(
            address(mockBeacon),
            address(token),
            feeRecipient,
            relayer,
            address(feeRule),
            MAX_DEADLINE_DELTA,
            OVERHEAD_GAS,
            REQUEST_EXPIRE_TIME
        );

        vm.stopPrank();

        // Mint tokens to user
        token.mint(user, 1000 ether);

        // Mint tokens to the test contract itself
        token.mint(address(this), 1000 ether);
    }

    function testInitialization() public view {
        assertEq(goatVRF.beacon(), address(mockBeacon));
        assertEq(goatVRF.wgoatbtcToken(), address(token));
        assertEq(goatVRF.feeRecipient(), feeRecipient);
        assertEq(goatVRF.relayer(), relayer);
        assertEq(goatVRF.feeRule(), address(feeRule));
        assertEq(goatVRF.maxDeadlineDelta(), MAX_DEADLINE_DELTA);
        assertEq(goatVRF.nextRequestId(), 1);
        assertEq(goatVRF.overheadGas(), OVERHEAD_GAS);
        assertEq(goatVRF.requestExpireTime(), REQUEST_EXPIRE_TIME);
    }

    function testRequestRandomness() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAllowedGasPrice = 100 gwei;
        uint256 callbackGas = 600000;

        // Approve tokens for fee
        uint256 fee = goatVRF.calculateFee(0);
        token.approve(address(goatVRF), fee);

        // Request randomness
        uint256 requestId = goatVRF.getNewRandom(deadline, maxAllowedGasPrice, callbackGas);

        // Verify request state
        assertEq(uint256(goatVRF.getRequestState(requestId)), uint256(IGoatVRF.RequestState.Pending));
    }

    function testRequestRandomnessWithInvalidDeadline() public {
        // Test deadline before genesis
        uint256 genesis = mockBeacon.genesisTimestamp();
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InvalidDeadline.selector, genesis - 1));
        goatVRF.getNewRandom(genesis - 1, 100 gwei, 600000);

        // Test deadline too far in future
        uint256 farDeadline = block.timestamp + goatVRF.maxDeadlineDelta() + 1;
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InvalidDeadline.selector, farDeadline));
        goatVRF.getNewRandom(farDeadline, 100 gwei, 600000);

        // Test deadline too close to current time
        uint256 tooCloseDeadline = block.timestamp + mockBeacon.period() - 1;
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InvalidDeadline.selector, tooCloseDeadline));
        goatVRF.getNewRandom(tooCloseDeadline, 100 gwei, 600000);
    }

    function testRequestRandomnessWithTooFarDeadline() public {
        uint256 deadline = block.timestamp + MAX_DEADLINE_DELTA + 1;
        uint256 maxAllowedGasPrice = 100 gwei;
        uint256 callbackGas = 600000;

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InvalidDeadline.selector, deadline));
        goatVRF.getNewRandom(deadline, maxAllowedGasPrice, callbackGas);
        vm.stopPrank();
    }

    function testFulfillRandomness() public {
        // Deploy mock consumer
        MockRandomnessConsumer consumer = new MockRandomnessConsumer(address(goatVRF));

        // Get beacon info
        uint256 genesis = mockBeacon.genesisTimestamp();
        uint256 period = mockBeacon.period();

        // Calculate valid deadline and round
        uint256 deadline = block.timestamp + period;
        uint256 delta = deadline - genesis;
        uint256 round = (delta / period) + ((delta % period > 0) ? 1 : 0);

        // Transfer tokens to consumer
        uint256 fee = goatVRF.calculateFee(600000);
        token.transfer(address(consumer), fee * 2); // Transfer with safety margin

        // Approve tokens for fee as the consumer
        vm.startPrank(address(consumer));
        token.approve(address(goatVRF), fee * 2); // Approve with safety margin
        vm.stopPrank();

        // Request randomness as the consumer
        vm.prank(address(consumer));
        uint256 requestId = goatVRF.getNewRandom(deadline, 100 gwei, 600000);

        console2.log("Request ID:", requestId);

        // Warp to after deadline
        vm.warp(deadline + 1);

        // Mock signature (64 bytes filled with 1s)
        bytes memory signature = new bytes(64);
        for (uint256 i = 0; i < 64; i++) {
            signature[i] = bytes1(uint8(1));
        }

        // Verify request state before fulfillment
        assertEq(uint256(goatVRF.getRequestState(requestId)), uint256(IGoatVRF.RequestState.Pending));

        // Fulfill randomness
        vm.prank(relayer);
        goatVRF.fulfillRequest(
            requestId,
            address(consumer), // Use the consumer address
            100 gwei,
            600000,
            round,
            signature
        );

        // Verify request state after fulfillment
        assertEq(uint256(goatVRF.getRequestState(requestId)), uint256(IGoatVRF.RequestState.Fulfilled));

        // Verify callback was successful
        assertTrue(consumer.callbackSucceeded(), "Callback should have succeeded");

        // Verify randomness was stored in consumer
        uint256 randomness = consumer.getRandomResult(requestId);
        assertTrue(randomness > 0, "Randomness should be non-zero");

        console2.log("Randomness result:", randomness);
    }

    function testFulfillRandomnessWithInvalidRequestId() public {
        uint256 invalidRequestId = 999;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAllowedGasPrice = 100 gwei;
        uint256 callbackGas = 600000;

        // Calculate round
        uint256 genesis = mockBeacon.genesisTimestamp();
        uint256 period = mockBeacon.period();
        uint256 delta = deadline - genesis;
        uint256 round = (delta / period) + ((delta % period > 0) ? 1 : 0);

        vm.warp(deadline + 1);
        vm.startPrank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.RequestNotPending.selector, invalidRequestId));
        goatVRF.fulfillRequest(invalidRequestId, user, maxAllowedGasPrice, callbackGas, round, hex"1234");
        vm.stopPrank();
    }

    function testFulfillRandomnessWithWrongGasPrice() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAllowedGasPrice = 100 gwei;
        uint256 callbackGas = 600000;

        vm.startPrank(user);
        token.approve(address(goatVRF), type(uint256).max);
        uint256 requestId = goatVRF.getNewRandom(deadline, maxAllowedGasPrice, callbackGas);
        vm.stopPrank();

        vm.warp(deadline + 1);

        // Calculate round
        uint256 genesis = mockBeacon.genesisTimestamp();
        uint256 period = mockBeacon.period();
        uint256 delta = deadline - genesis;
        uint256 round = (delta / period) + ((delta % period > 0) ? 1 : 0);

        uint256 wrongGasPrice = maxAllowedGasPrice + 1;
        vm.startPrank(relayer);
        vm.txGasPrice(wrongGasPrice);
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InvalidGasPrice.selector, wrongGasPrice));
        goatVRF.fulfillRequest(requestId, user, maxAllowedGasPrice, callbackGas, round, new bytes(96));
        vm.stopPrank();
    }

    function testFulfillRandomnessWithWrongUser() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAllowedGasPrice = 100 gwei;
        uint256 callbackGas = 600000;

        vm.chainId(555);

        vm.startPrank(user);
        token.approve(address(goatVRF), type(uint256).max);
        uint256 requestId = goatVRF.getNewRandom(deadline, maxAllowedGasPrice, callbackGas);
        vm.stopPrank();

        vm.warp(deadline + 1);

        address wrongUser = address(5);
        bytes32 wrongHash =
            keccak256(abi.encode(555, address(goatVRF), requestId, wrongUser, maxAllowedGasPrice, callbackGas, 0));

        vm.startPrank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InvalidRequestHash.selector, wrongHash));
        goatVRF.fulfillRequest(requestId, wrongUser, maxAllowedGasPrice, callbackGas, 0, new bytes(96));
        vm.stopPrank();
    }

    function testCancelRequest() public {
        // Get beacon info
        uint256 period = mockBeacon.period();

        // Calculate valid deadline and round
        uint256 deadline = block.timestamp + period;

        // Approve tokens for fee
        uint256 fee = goatVRF.calculateFee(0);
        token.approve(address(goatVRF), fee);

        // Request randomness
        uint256 requestId = goatVRF.getNewRandom(deadline, 100 gwei, 600000);

        // Cancel request
        goatVRF.cancelRequest(requestId);

        // Verify request state
        assertEq(uint256(goatVRF.getRequestState(requestId)), uint256(IGoatVRF.RequestState.Cancelled));
    }

    function testCancelRequestNotPending() public {
        // Get beacon info
        uint256 period = mockBeacon.period();

        // Calculate valid deadline and round
        uint256 deadline = block.timestamp + period;

        // Approve tokens for fee
        uint256 fee = goatVRF.calculateFee(0);
        token.approve(address(goatVRF), fee);

        // Request randomness
        uint256 requestId = goatVRF.getNewRandom(deadline, 100 gwei, 600000);

        // Cancel request
        goatVRF.cancelRequest(requestId);

        // Try to cancel again
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.RequestNotPending.selector, requestId));
        goatVRF.cancelRequest(requestId);
    }

    function testCancelRequestUnauthorized() public {
        // Get beacon info
        uint256 period = mockBeacon.period();

        // Calculate valid deadline and round
        uint256 deadline = block.timestamp + period;

        // Approve tokens for fee
        uint256 fee = goatVRF.calculateFee(0);
        token.approve(address(goatVRF), fee);

        // Request randomness
        uint256 requestId = goatVRF.getNewRandom(deadline, 100 gwei, 600000);

        // Try to cancel from unauthorized address
        vm.prank(address(0xdead));
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InvalidUser.selector, address(0xdead)));
        goatVRF.cancelRequest(requestId);
    }

    // Test cancellation by owner - should not be allowed anymore
    function testCancelRequestByOwner() public {
        // Get beacon info
        uint256 period = mockBeacon.period();

        // Calculate valid deadline and round
        uint256 deadline = block.timestamp + period;

        // Approve tokens for fee
        uint256 fee = goatVRF.calculateFee(0);
        token.approve(address(goatVRF), fee);

        // Request randomness
        uint256 requestId = goatVRF.getNewRandom(deadline, 100 gwei, 600000);

        // Try to cancel from owner address (should fail with the updated contract)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InvalidUser.selector, owner));
        goatVRF.cancelRequest(requestId);
    }

    function testRequestRandomnessWithZeroBalance() public {
        // Request should revert with zero balance since we need to pay a fee
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAllowedGasPrice = 100 gwei;
        uint256 callbackGas = 600000;

        address poorUser = address(1234);

        // Make sure poorUser has no tokens
        vm.startPrank(poorUser);
        token.approve(address(goatVRF), type(uint256).max);

        // In the modified implementation, this request should revert
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InsufficientBalance.selector, 0, FIXED_FEE));
        goatVRF.getNewRandom(deadline, maxAllowedGasPrice, callbackGas);
        vm.stopPrank();
    }

    function testConfigSetters() public {
        // Prepare new config values
        address newBeacon = address(0x1234);
        address newToken = address(0x2345);
        address newFeeRecipient = address(0x3456);
        address newRelayer = address(0x4567);
        address newFeeRule = address(0x5678);
        uint256 newMaxDeadlineDelta = 10 days;
        uint256 newOverheadGas = 100000;
        uint256 newRequestExpireTime = 14 days;

        vm.startPrank(owner);

        // Test setBeacon
        vm.expectEmit(true, true, true, true);
        emit ConfigUpdated("beacon", abi.encode(newBeacon));
        goatVRF.setBeacon(newBeacon);
        assertEq(goatVRF.beacon(), newBeacon);

        // Test setWgoatbtcToken
        vm.expectEmit(true, true, true, true);
        emit ConfigUpdated("token", abi.encode(newToken));
        goatVRF.setWgoatbtcToken(newToken);
        assertEq(goatVRF.wgoatbtcToken(), newToken);

        // Test setFeeRecipient
        vm.expectEmit(true, true, true, true);
        emit ConfigUpdated("feeRecipient", abi.encode(newFeeRecipient));
        goatVRF.setFeeRecipient(newFeeRecipient);
        assertEq(goatVRF.feeRecipient(), newFeeRecipient);

        // Test setRelayer
        vm.expectEmit(true, true, true, true);
        emit ConfigUpdated("relayer", abi.encode(newRelayer));
        goatVRF.setRelayer(newRelayer);
        assertEq(goatVRF.relayer(), newRelayer);

        // Test setFeeRule
        vm.expectEmit(true, true, true, true);
        emit ConfigUpdated("feeRule", abi.encode(newFeeRule));
        goatVRF.setFeeRule(newFeeRule);
        assertEq(goatVRF.feeRule(), newFeeRule);

        // Test setMaxDeadlineDelta
        vm.expectEmit(true, true, true, true);
        emit ConfigUpdated("maxDeadlineDelta", abi.encode(newMaxDeadlineDelta));
        goatVRF.setMaxDeadlineDelta(newMaxDeadlineDelta);
        assertEq(goatVRF.maxDeadlineDelta(), newMaxDeadlineDelta);

        // Test setOverheadGas
        vm.expectEmit(true, true, true, true);
        emit ConfigUpdated("overheadGas", abi.encode(newOverheadGas));
        goatVRF.setOverheadGas(newOverheadGas);
        assertEq(goatVRF.overheadGas(), newOverheadGas);

        // Test setRequestExpireTime
        vm.expectEmit(true, true, true, true);
        emit ConfigUpdated("requestExpireTime", abi.encode(newRequestExpireTime));
        goatVRF.setRequestExpireTime(newRequestExpireTime);
        assertEq(goatVRF.requestExpireTime(), newRequestExpireTime);

        vm.stopPrank();
    }

    // Test invalid config settings
    function testInvalidConfigSetters() public {
        vm.startPrank(owner);

        // Test invalid beacon
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InvalidBeacon.selector, address(0)));
        goatVRF.setBeacon(address(0));

        // Test invalid token
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InvalidToken.selector, address(0)));
        goatVRF.setWgoatbtcToken(address(0));

        // Test invalid fee recipient
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InvalidFeeRecipient.selector, address(0)));
        goatVRF.setFeeRecipient(address(0));

        // Test invalid relayer
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InvalidRelayer.selector, address(0)));
        goatVRF.setRelayer(address(0));

        // Test invalid fee rule
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InvalidFeeRule.selector, address(0)));
        goatVRF.setFeeRule(address(0));

        // Test invalid request expire time (0)
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InvalidRequestExpireTime.selector, 0));
        goatVRF.setRequestExpireTime(0);

        vm.stopPrank();
    }

    // Test unauthorized access to config setters
    function testUnauthorizedConfigSetters() public {
        address unauthorized = address(0x9999);

        vm.startPrank(unauthorized);

        // Test all config setters
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        goatVRF.setBeacon(address(0x1111));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        goatVRF.setWgoatbtcToken(address(0x1111));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        goatVRF.setFeeRecipient(address(0x1111));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        goatVRF.setRelayer(address(0x1111));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        goatVRF.setFeeRule(address(0x1111));

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        goatVRF.setMaxDeadlineDelta(1);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        goatVRF.setOverheadGas(1);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, unauthorized));
        goatVRF.setRequestExpireTime(1 days);

        vm.stopPrank();
    }

    function testFulfillRandomnessWithInsufficientAllowance() public {
        // First request randomness
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAllowedGasPrice = 100 gwei;
        uint256 callbackGas = 600000;

        vm.startPrank(user);
        token.approve(address(goatVRF), type(uint256).max);
        uint256 requestId = goatVRF.getNewRandom(deadline, maxAllowedGasPrice, callbackGas);
        // Set allowance to zero after request
        token.approve(address(goatVRF), 0);
        vm.stopPrank();

        vm.warp(deadline + 1);

        // Calculate round
        uint256 genesis = mockBeacon.genesisTimestamp();
        uint256 period = mockBeacon.period();
        uint256 delta = deadline - genesis;
        uint256 round = (delta / period) + ((delta % period > 0) ? 1 : 0);

        // Fulfillment should revert due to insufficient allowance
        vm.startPrank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InsufficientAllowance.selector, 0, FIXED_FEE));
        goatVRF.fulfillRequest(requestId, user, maxAllowedGasPrice, callbackGas, round, new bytes(96));
        vm.stopPrank();
    }

    function testFulfillRandomnessWithInsufficientBalance() public {
        // First request randomness
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAllowedGasPrice = 100 gwei;
        uint256 callbackGas = 600000;

        vm.startPrank(user);
        token.approve(address(goatVRF), type(uint256).max);
        uint256 requestId = goatVRF.getNewRandom(deadline, maxAllowedGasPrice, callbackGas);
        // Transfer all tokens away to simulate insufficient balance
        token.transfer(address(0), token.balanceOf(user));
        vm.stopPrank();

        vm.warp(deadline + 1);

        // Calculate round
        uint256 genesis = mockBeacon.genesisTimestamp();
        uint256 period = mockBeacon.period();
        uint256 delta = deadline - genesis;
        uint256 round = (delta / period) + ((delta % period > 0) ? 1 : 0);

        // Fulfillment should revert due to insufficient balance
        vm.startPrank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.InsufficientBalance.selector, 0, FIXED_FEE));
        goatVRF.fulfillRequest(requestId, user, maxAllowedGasPrice, callbackGas, round, new bytes(96));
        vm.stopPrank();
    }

    // Test fulfilling randomness with expired request
    function testFulfillRandomnessWithExpiredRequest() public {
        // Request randomness
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAllowedGasPrice = 100 gwei;
        uint256 callbackGas = 600000;

        vm.startPrank(user);
        token.approve(address(goatVRF), type(uint256).max);
        uint256 requestId = goatVRF.getNewRandom(deadline, maxAllowedGasPrice, callbackGas);
        vm.stopPrank();

        // Warp to after deadline and expiration
        vm.warp(block.timestamp + REQUEST_EXPIRE_TIME + 1);

        // Calculate round
        uint256 genesis = mockBeacon.genesisTimestamp();
        uint256 period = mockBeacon.period();
        uint256 delta = deadline - genesis;
        uint256 round = (delta / period) + ((delta % period > 0) ? 1 : 0);

        // Attempt to fulfill expired request
        vm.startPrank(relayer);
        vm.expectRevert(abi.encodeWithSelector(IGoatVRF.RequestExpired.selector, REQUEST_EXPIRE_TIME));
        goatVRF.fulfillRequest(requestId, user, maxAllowedGasPrice, callbackGas, round, new bytes(96));
        vm.stopPrank();
    }

    // Test getting request timestamp
    function testGetRequestTimestamp() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAllowedGasPrice = 100 gwei;
        uint256 callbackGas = 600000;

        // Approve tokens for fee
        uint256 fee = goatVRF.calculateFee(0);
        token.approve(address(goatVRF), fee);

        // Request randomness
        uint256 requestId = goatVRF.getNewRandom(deadline, maxAllowedGasPrice, callbackGas);

        // Verify request timestamp
        assertEq(goatVRF.getRequestTimestamp(requestId), block.timestamp);
    }

    // Test calculateFeeWithGasPrice method
    function testCalculateFeeWithGasPrice() public view {
        // Test parameters
        uint256 gasAmount = 600000;
        uint256[] memory gasPrices = new uint256[](4);
        gasPrices[0] = 10 gwei;
        gasPrices[1] = 50 gwei;
        gasPrices[2] = 100 gwei;
        gasPrices[3] = 200 gwei;

        console2.log("===== Testing calculateFeeWithGasPrice =====");
        console2.log("Fixed Fee: %d", FIXED_FEE);
        console2.log("Overhead Gas: %d", OVERHEAD_GAS);
        console2.log("Gas Amount: %d", gasAmount);

        for (uint256 i = 0; i < gasPrices.length; i++) {
            uint256 gasPrice = gasPrices[i];
            uint256 fee = goatVRF.calculateFeeWithGasPrice(gasAmount, gasPrice);

            // Calculate expected fee
            uint256 expectedGasFee = (gasAmount + OVERHEAD_GAS) * gasPrice;
            uint256 expectedTotalFee = FIXED_FEE + expectedGasFee;

            console2.log("\nGas Price: %d gwei", gasPrice / 1 gwei);
            console2.log("Calculated Fee: %d wei", fee);
            console2.log("Expected Fee: %d wei", expectedTotalFee);
            console2.log("Fee Breakdown: Fixed(%d) + Gas(%d)", FIXED_FEE, expectedGasFee);

            // Verify fee calculation
            assertEq(fee, expectedTotalFee, "Fee calculation mismatch");

            // Compare with DeployConsumer.s.sol approach
            if (gasPrice == 50 gwei) {
                uint256 safetyFactor = 2;
                uint256 finalEstimatedFee = fee * safetyFactor;
                console2.log("With safety factor (%dx): %d wei", safetyFactor, finalEstimatedFee);
            }
        }

        // Compare with standard calculateFee method
        uint256 standardFee = goatVRF.calculateFee(gasAmount);
        uint256 customFee = goatVRF.calculateFeeWithGasPrice(gasAmount, tx.gasprice);

        console2.log("\nComparing standard vs custom method with tx.gasprice (%d):", tx.gasprice);
        console2.log("calculateFee: %d", standardFee);
        console2.log("calculateFeeWithGasPrice: %d", customFee);
        assertEq(standardFee, customFee, "Methods should return same value with same gas price");
    }

    function testGasMeasurement() public {
        uint256 callbackGas = 600000;

        uint256[] memory gasEstimates = new uint256[](5);
        gasEstimates[0] = 0;
        gasEstimates[1] = 100000;
        gasEstimates[2] = 600000;
        gasEstimates[3] = 1000000;
        gasEstimates[4] = 2000000;

        console2.log("===== Fee Estimation Test =====");
        console2.log("Fixed Fee (FIXED_FEE): %d", FIXED_FEE);
        console2.log("Overhead Gas (OVERHEAD_GAS): %d", OVERHEAD_GAS);
        console2.log("Current gas price: %d", tx.gasprice);

        for (uint256 i = 0; i < gasEstimates.length; i++) {
            uint256 fee = goatVRF.calculateFee(gasEstimates[i]);
            console2.log("Estimated Gas: %d, Calculated Fee: %d", gasEstimates[i], fee);

            if (gasEstimates[i] > 0) {
                uint256 expectedGasFee = (gasEstimates[i] + OVERHEAD_GAS) * tx.gasprice;
                uint256 expectedTotalFee = FIXED_FEE + expectedGasFee;
                console2.log(
                    "Expected fee breakdown: Fixed Fee(%d) + Gas Fee(%d) = Total Fee(%d)",
                    FIXED_FEE,
                    expectedGasFee,
                    expectedTotalFee
                );
                assert(fee == expectedTotalFee);
            }
        }

        console2.log("\n===== Fee Estimation with Custom Gas Price Test =====");
        uint256[] memory customGasPrices = new uint256[](3);
        customGasPrices[0] = 30 gwei;
        customGasPrices[1] = 50 gwei;
        customGasPrices[2] = 100 gwei;

        uint256 testGasUsed = 600000;

        for (uint256 i = 0; i < customGasPrices.length; i++) {
            uint256 customGasPrice = customGasPrices[i];
            uint256 fee = goatVRF.calculateFeeWithGasPrice(testGasUsed, customGasPrice);

            uint256 expectedGasFee = (testGasUsed + OVERHEAD_GAS) * customGasPrice;
            uint256 expectedTotalFee = FIXED_FEE + expectedGasFee;

            console2.log("Gas Price: %d gwei, Calculated Fee: %d", customGasPrice / 1 gwei, fee);
            console2.log(
                "Expected fee breakdown: Fixed Fee(%d) + Gas Fee(%d) = Total Fee(%d)",
                FIXED_FEE,
                expectedGasFee,
                expectedTotalFee
            );

            assert(fee == expectedTotalFee);
        }

        uint256 txGasPrice = tx.gasprice;
        uint256 feeWithTxGasPrice = goatVRF.calculateFee(testGasUsed);
        uint256 feeWithCustomGasPrice = goatVRF.calculateFeeWithGasPrice(testGasUsed, txGasPrice);

        console2.log("Fee comparison with same gas price:");
        console2.log("- calculateFee(%d): %d", testGasUsed, feeWithTxGasPrice);
        console2.log("- calculateFeeWithGasPrice(%d, %d): %d", testGasUsed, txGasPrice, feeWithCustomGasPrice);
        assert(feeWithTxGasPrice == feeWithCustomGasPrice);

        console2.log("\n===== Actual Gas Consumption Test =====");

        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAllowedGasPrice = 100 gwei;

        vm.startPrank(user);
        token.approve(address(goatVRF), type(uint256).max);

        console2.log("Step 1: Request randomness");
        uint256 preRequestBalance = token.balanceOf(user);
        uint256 requestId = goatVRF.getNewRandom(deadline, maxAllowedGasPrice, callbackGas);
        uint256 postRequestBalance = token.balanceOf(user);
        uint256 requestCost = preRequestBalance - postRequestBalance;
        console2.log("Request ID: %d", requestId);
        console2.log("Request cost: %d", requestCost);

        vm.stopPrank();

        uint256 genesis = mockBeacon.genesisTimestamp();
        uint256 period = mockBeacon.period();
        uint256 delta = deadline - genesis;
        uint256 round = (delta / period) + ((delta % period > 0) ? 1 : 0);

        vm.warp(deadline + 1);

        bytes memory signature = new bytes(96);

        vm.startPrank(relayer);

        uint256 fulfillGasPrice = 50 gwei;
        vm.txGasPrice(fulfillGasPrice);
        console2.log("Fulfill gas price: %d gwei", fulfillGasPrice / 1 gwei);

        console2.log("Step 2: Fulfill randomness request");

        uint256 preFulfillBalance = token.balanceOf(user);
        uint256 initialGas = gasleft();

        goatVRF.fulfillRequest(requestId, user, maxAllowedGasPrice, callbackGas, round, signature);

        uint256 gasUsed = initialGas - gasleft();
        console2.log("Actual gas used: %d", gasUsed);

        uint256 postFulfillBalance = token.balanceOf(user);
        uint256 fulfillCost = preFulfillBalance - postFulfillBalance;
        console2.log("Fulfill cost: %d", fulfillCost);

        uint256 expectedFulfillGasFee = (gasUsed + OVERHEAD_GAS) * fulfillGasPrice;
        uint256 expectedFulfillTotalFee = FIXED_FEE + expectedFulfillGasFee;
        console2.log("Expected fulfill cost breakdown:");
        console2.log("- Fixed fee: %d", FIXED_FEE);
        console2.log("- Gas used: %d", gasUsed);
        console2.log("- Gas with overhead: %d", gasUsed + OVERHEAD_GAS);
        console2.log("- Gas fee: %d", expectedFulfillGasFee);
        console2.log("- Expected total fee: %d", expectedFulfillTotalFee);
        console2.log("- Actual fee: %d", fulfillCost);

        int256 diffAmount = int256(fulfillCost) - int256(expectedFulfillTotalFee);
        console2.log("Fee difference: %d", diffAmount);

        uint256 consumerEstimatedFee = goatVRF.calculateFee(600000);
        console2.log("\n===== DeployConsumer Simulation =====");
        console2.log("DeployConsumer estimated fee (calculateFee(600000)): %d", consumerEstimatedFee);

        uint256 safeGasPrice = 50 gwei;
        uint256 consumerEstimatedFeeWithGasPrice = goatVRF.calculateFeeWithGasPrice(600000, safeGasPrice);
        console2.log(
            "DeployConsumer estimated fee with custom gas price (calculateFeeWithGasPrice(600000, %d gwei)): %d",
            safeGasPrice / 1 gwei,
            consumerEstimatedFeeWithGasPrice
        );

        uint256 safetyFactor = 2;
        uint256 safeEstimatedFee = consumerEstimatedFeeWithGasPrice * safetyFactor;
        console2.log("Estimated fee with safety factor (%d): %d", safetyFactor, safeEstimatedFee);

        console2.log("Actual fee: %d", fulfillCost);
        console2.log("Difference ratio with normal calculation: %d times", fulfillCost / consumerEstimatedFee);
        console2.log("Difference ratio with custom gas price: %d times", fulfillCost / consumerEstimatedFeeWithGasPrice);
        console2.log("Difference ratio with safety factor: %d times", fulfillCost / safeEstimatedFee);

        vm.stopPrank();
    }

    // Test request with valid parameters
    function testRequestWithValidParams() public {
        uint256 deadline = block.timestamp + 1 hours;
        uint256 maxAllowedGasPrice = 100 gwei;
        uint256 callbackGas = 600000;

        vm.startPrank(user);
        token.approve(address(goatVRF), type(uint256).max);
        uint256 requestId = goatVRF.getNewRandom(deadline, maxAllowedGasPrice, callbackGas);
        vm.stopPrank();

        // Verify request details
        (address requester, IGoatVRF.RequestState state) = goatVRF.getRequestDetails(requestId);
        assertEq(requester, user);
        assertEq(uint256(state), uint256(IGoatVRF.RequestState.Pending));

        // Verify request timestamp
        assertEq(goatVRF.getRequestTimestamp(requestId), block.timestamp);
    }

    // Test fulfilling randomness with failing callback
    function testFulfillRandomnessWithFailingCallback() public {
        // Deploy mock failing consumer
        MockFailingConsumer consumer = new MockFailingConsumer(address(goatVRF));

        // Get beacon info
        uint256 genesis = mockBeacon.genesisTimestamp();
        uint256 period = mockBeacon.period();

        // Calculate valid deadline and round
        uint256 deadline = block.timestamp + period;
        uint256 delta = deadline - genesis;
        uint256 round = (delta / period) + ((delta % period > 0) ? 1 : 0);

        // Transfer tokens to consumer
        uint256 fee = goatVRF.calculateFee(600000);
        token.transfer(address(consumer), fee * 2); // Transfer with safety margin

        // Approve tokens for fee as the consumer
        vm.startPrank(address(consumer));
        token.approve(address(goatVRF), fee * 2); // Approve with safety margin
        vm.stopPrank();

        // Request randomness as the consumer
        vm.prank(address(consumer));
        uint256 requestId = goatVRF.getNewRandom(deadline, 100 gwei, 600000);

        console2.log("Request ID for failing callback:", requestId);

        // Warp to after deadline
        vm.warp(deadline + 1);

        // Mock signature
        bytes memory signature = new bytes(64);
        for (uint256 i = 0; i < 64; i++) {
            signature[i] = bytes1(uint8(1));
        }

        // Fulfill randomness - this should handle the callback failure properly
        vm.prank(relayer);
        goatVRF.fulfillRequest(requestId, address(consumer), 100 gwei, 600000, round, signature);

        // Verify request state changed to Failed (not Fulfilled)
        assertEq(
            uint256(goatVRF.getRequestState(requestId)),
            uint256(IGoatVRF.RequestState.Failed),
            "Request should be marked as Failed when callback reverts"
        );

        console2.log("Verified that request state is correctly set to Failed when callback fails");
    }

    function testFulfillRandomnessWithAdvancedConsumer() public {
        // Deploy mock advanced consumer
        MockAdvancedConsumer consumer = new MockAdvancedConsumer(address(goatVRF));

        // Get beacon info
        uint256 genesis = mockBeacon.genesisTimestamp();
        uint256 period = mockBeacon.period();

        // Calculate valid deadline and round
        uint256 deadline = block.timestamp + period;
        uint256 delta = deadline - genesis;
        uint256 round = (delta / period) + ((delta % period > 0) ? 1 : 0);

        // Transfer tokens to consumer
        uint256 fee = goatVRF.calculateFee(600000);
        token.transfer(address(consumer), fee * 2); // Transfer with safety margin

        // Approve tokens for fee as the consumer
        vm.startPrank(address(consumer));
        token.approve(address(goatVRF), fee * 2); // Approve with safety margin
        vm.stopPrank();

        // Request randomness as the consumer
        vm.prank(address(consumer));
        uint256 requestId = goatVRF.getNewRandom(deadline, 100 gwei, 600000);

        console2.log("Request ID for advanced consumer:", requestId);

        // Warp to after deadline
        vm.warp(deadline + 1);

        // Mock signature
        bytes memory signature = new bytes(64);
        for (uint256 i = 0; i < 64; i++) {
            signature[i] = bytes1(uint8(i % 256)); // More varied signature pattern
        }

        // Fulfill randomness - this should complete successfully
        vm.prank(relayer);
        goatVRF.fulfillRequest(requestId, address(consumer), 100 gwei, 600000, round, signature);

        // Verify request state changed to Fulfilled
        assertEq(
            uint256(goatVRF.getRequestState(requestId)),
            uint256(IGoatVRF.RequestState.Fulfilled),
            "Request should be marked as Fulfilled"
        );

        // Verify callback was successful
        assertTrue(consumer.callbackSucceeded(), "Callback should have succeeded");

        // Verify randomness was stored in consumer
        uint256 randomness = consumer.getRandomResult(requestId);
        assertTrue(randomness > 0, "Randomness should be non-zero");

        // Get and verify the derived values
        uint256[] memory derivedValues = consumer.getDerivedValues(requestId);
        assertEq(derivedValues.length, 5, "Should have 5 derived values");

        // Log gas used by the callback
        console2.log("Gas used by advanced callback:", consumer.lastGasUsed());

        // Log the randomness and derived values
        console2.log("Original randomness:", randomness);
        console2.log("Derived values:");
        for (uint256 i = 0; i < derivedValues.length; i++) {
            console2.log("  Value", i, ":", derivedValues[i]);
        }
    }
}
