// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/APROBTCFeeRule.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock price feed for testing
contract MockAggregatorV3 is IAggregatorV3 {
    int256 private _price;
    uint8 private _decimals;
    string private _description;
    uint256 private _updateTime;
    uint80 private _roundId;

    constructor(int256 initialPrice, uint8 decimals_) {
        _price = initialPrice;
        _decimals = decimals_;
        _description = "Mock BTC/USD Price Feed";
        _updateTime = block.timestamp;
        _roundId = 1;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function description() external view override returns (string memory) {
        return _description;
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 _round)
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_round, _price, _updateTime, _updateTime, _roundId);
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (_roundId, _price, _updateTime, _updateTime, _roundId);
    }

    // Functions for testing
    function setPrice(int256 newPrice) external {
        _price = newPrice;
        _updateTime = block.timestamp;
        _roundId++;
    }

    function setDecimals(uint8 newDecimals) external {
        _decimals = newDecimals;
    }

    function setUpdateTime(uint256 newUpdateTime) external {
        _updateTime = newUpdateTime;
    }
}

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, 1000000 * 10 ** decimals_);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}

contract APROBTCFeeRuleTest is Test {
    APROBTCFeeRule public feeRule;
    MockAggregatorV3 public priceFeed;
    MockERC20 public feeToken;
    address public owner = address(1);
    address public user = address(2);

    // Test constants
    uint256 public constant TARGET_VALUE = 0.1 ether; // $0.1 USD
    int256 public constant INITIAL_BTC_PRICE = 87818 * 10 ** 8; // $87,818 with 8 decimals
    uint8 public constant PRICE_FEED_DECIMALS = 8;
    uint8 public constant TOKEN_DECIMALS = 18;

    function setUp() public {
        vm.startPrank(owner);

        // Create mock token
        feeToken = new MockERC20("Bitcoin", "BTC", TOKEN_DECIMALS);

        // Create mock price feed
        priceFeed = new MockAggregatorV3(INITIAL_BTC_PRICE, PRICE_FEED_DECIMALS);

        // Create fee rule
        feeRule = new APROBTCFeeRule(TARGET_VALUE, address(feeToken), address(priceFeed));

        vm.stopPrank();
    }

    function testInitialization() public view {
        assertEq(feeRule.targetValue(), TARGET_VALUE);
        assertEq(feeRule.owner(), owner);
        assertEq(feeRule.priceFeed(), address(priceFeed));
        assertEq(feeRule.feeToken(), address(feeToken));
        assertEq(feeRule.decimals(), PRICE_FEED_DECIMALS);
    }

    function testCalculateFeeWithZeroGasUsed() public view {
        // Calculate expected fee: (TARGET_VALUE * 10^TOKEN_DECIMALS) / BTC_PRICE
        // = (0.1 * 10^18 * 10^18) / (87818 * 10^8)
        // = 0.000000113870912512 BTC (approximately)
        uint256 expectedFee = (TARGET_VALUE * (10 ** TOKEN_DECIMALS)) / uint256(INITIAL_BTC_PRICE);

        uint256 fee = feeRule.calculateFeeWithGasPrice(user, 0, 0);
        assertEq(fee, expectedFee);
    }

    function testCalculateFeeWithGasUsed() public {
        uint256 gasUsed = 100000;
        uint256 gasPrice = 50 gwei;
        vm.txGasPrice(gasPrice);

        // Calculate expected base fee
        uint256 expectedBaseFee = (TARGET_VALUE * (10 ** TOKEN_DECIMALS)) / uint256(INITIAL_BTC_PRICE);
        uint256 expectedGasFee = gasUsed * gasPrice;
        uint256 expectedTotalFee = expectedBaseFee + expectedGasFee;

        uint256 actualFee = feeRule.calculateFee(user, gasUsed);
        assertEq(actualFee, expectedTotalFee);
    }

    function testCalculateFeeWithGasPrice() public view {
        uint256 gasUsed = 100000;
        uint256 customGasPrice = 100 gwei;

        // Calculate expected base fee
        uint256 expectedBaseFee = (TARGET_VALUE * (10 ** TOKEN_DECIMALS)) / uint256(INITIAL_BTC_PRICE);
        uint256 expectedGasFee = gasUsed * customGasPrice;
        uint256 expectedTotalFee = expectedBaseFee + expectedGasFee;

        uint256 actualFee = feeRule.calculateFeeWithGasPrice(user, gasUsed, customGasPrice);
        assertEq(actualFee, expectedTotalFee);
    }

    function testCalculateFeeWithGasPriceVsActualGasPrice() public {
        uint256 gasUsed = 100000;
        uint256 customGasPrice = 100 gwei;
        vm.txGasPrice(50 gwei); // Actual gas price different from custom

        uint256 feeWithTxGasPrice = feeRule.calculateFee(user, gasUsed);
        uint256 feeWithCustomGasPrice = feeRule.calculateFeeWithGasPrice(user, gasUsed, customGasPrice);

        // Fee with custom gas price should be different
        assertTrue(feeWithCustomGasPrice != feeWithTxGasPrice);

        // Calculate expected base fee
        uint256 expectedBaseFee = (TARGET_VALUE * (10 ** TOKEN_DECIMALS)) / uint256(INITIAL_BTC_PRICE);

        // Fee with custom gas price
        uint256 expectedCustomFee = expectedBaseFee + (gasUsed * customGasPrice);
        assertEq(feeWithCustomGasPrice, expectedCustomFee);

        // Fee with tx.gasprice
        uint256 expectedTxFee = expectedBaseFee + (gasUsed * tx.gasprice);
        assertEq(feeWithTxGasPrice, expectedTxFee);
    }

    function testSetTargetValue() public {
        uint256 newTargetValue = 0.2 ether;

        vm.prank(owner);
        feeRule.setTargetValue(newTargetValue);

        assertEq(feeRule.targetValue(), newTargetValue);
    }

    function testCannotSetZeroTargetValue() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(APROBTCFeeRule.InvalidFee.selector, 0));
        feeRule.setTargetValue(0);
    }

    function testOnlyOwnerCanSetTargetValue() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        feeRule.setTargetValue(0.2 ether);
    }

    function testSetPriceFeed() public {
        MockAggregatorV3 newPriceFeed = new MockAggregatorV3(INITIAL_BTC_PRICE, PRICE_FEED_DECIMALS);

        vm.prank(owner);
        feeRule.setPriceFeed(address(newPriceFeed));

        assertEq(feeRule.priceFeed(), address(newPriceFeed));
    }

    function testCannotSetZeroAddressPriceFeed() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(APROBTCFeeRule.InvalidPriceFeed.selector, address(0)));
        feeRule.setPriceFeed(address(0));
    }

    function testCannotSetPriceFeedWithZeroDecimals() public {
        MockAggregatorV3 invalidPriceFeed = new MockAggregatorV3(INITIAL_BTC_PRICE, 0);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(APROBTCFeeRule.InvalidPriceFeed.selector, address(invalidPriceFeed)));
        feeRule.setPriceFeed(address(invalidPriceFeed));
    }

    function testSetFeeToken() public {
        MockERC20 newFeeToken = new MockERC20("New Bitcoin", "NBTC", TOKEN_DECIMALS);

        vm.prank(owner);
        feeRule.setFeeToken(address(newFeeToken));

        assertEq(feeRule.feeToken(), address(newFeeToken));
    }

    function testCannotSetZeroAddressFeeToken() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(APROBTCFeeRule.InvalidFeeToken.selector, address(0)));
        feeRule.setFeeToken(address(0));
    }

    // Test price changes affecting fee calculation
    function testCalculateFeeWithPriceChange() public {
        // Initial calculation
        uint256 initialExpectedFee = (TARGET_VALUE * (10 ** TOKEN_DECIMALS)) / uint256(INITIAL_BTC_PRICE);
        uint256 initialFee = feeRule.calculateFeeWithGasPrice(user, 0, 0);
        assertEq(initialFee, initialExpectedFee);

        // Change price to half the original
        int256 newPrice = INITIAL_BTC_PRICE / 2;
        priceFeed.setPrice(newPrice);

        // New calculation - fee should double
        uint256 newExpectedFee = (TARGET_VALUE * (10 ** TOKEN_DECIMALS)) / uint256(newPrice);
        uint256 newFee = feeRule.calculateFeeWithGasPrice(user, 0, 0);
        assertEq(newFee, newExpectedFee);

        // The new fee should be approximately twice the initial fee
        assertEq(newFee, initialFee * 2);
    }

    // Test error cases
    function testInvalidPriceFeedAnswer() public {
        // Set price to zero
        priceFeed.setPrice(0);

        vm.expectRevert(abi.encodeWithSelector(APROBTCFeeRule.InvalidPriceFeedAnswer.selector, 2));
        feeRule.calculateFee(user, 100000);
    }

    function testIncompleteRound() public {
        // Set update time to zero
        priceFeed.setUpdateTime(0);

        vm.expectRevert(abi.encodeWithSelector(APROBTCFeeRule.IncompleteRound.selector, 1));
        feeRule.calculateFee(user, 100000);
    }

    function testPriceFeedDecimalsMismatch() public {
        // Change price feed decimals
        priceFeed.setDecimals(10); // Different from initial 8

        vm.expectRevert(abi.encodeWithSelector(APROBTCFeeRule.PriceFeedDecimalsMismatch.selector, 10, 8));
        feeRule.calculateFee(user, 100000);
    }

    // Edge cases
    function testCalculateFeeWithExtremeValues() public view {
        uint256 gasUsed = 1_000_000;
        uint256 customGasPrice = 1000 gwei;

        // Calculate expected base fee
        uint256 expectedBaseFee = (TARGET_VALUE * (10 ** TOKEN_DECIMALS)) / uint256(INITIAL_BTC_PRICE);
        uint256 expectedGasFee = gasUsed * customGasPrice;
        uint256 expectedTotalFee = expectedBaseFee + expectedGasFee;

        uint256 actualFee = feeRule.calculateFeeWithGasPrice(user, gasUsed, customGasPrice);
        assertEq(actualFee, expectedTotalFee);
    }

    function testConstructWithMaxValues() public {
        uint256 maxTargetValue = type(uint256).max / (10 ** TOKEN_DECIMALS); // Avoid overflow in calculation

        vm.startPrank(owner);
        APROBTCFeeRule newFeeRule = new APROBTCFeeRule(maxTargetValue, address(feeToken), address(priceFeed));
        vm.stopPrank();

        assertEq(newFeeRule.targetValue(), maxTargetValue);
    }
}
