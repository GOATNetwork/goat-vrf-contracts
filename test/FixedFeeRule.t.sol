// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Test.sol";
import "../src/FixedFeeRule.sol";

contract FixedFeeRuleTest is Test {
    FixedFeeRule public feeRule;
    address public owner = address(1);
    address public user = address(2);

    uint256 public constant INITIAL_FIXED_FEE = 1 ether;

    function setUp() public {
        vm.startPrank(owner);
        feeRule = new FixedFeeRule(INITIAL_FIXED_FEE);
        vm.stopPrank();
    }

    function testInitialization() public view {
        assertEq(feeRule.fixedFee(), INITIAL_FIXED_FEE);
    }

    function testCalculateFeeWithZeroGasUsed() public view {
        uint256 fee = feeRule.calculateFee(user, 0);
        assertEq(fee, INITIAL_FIXED_FEE);
    }

    function testCalculateFeeWithGasUsed() public {
        uint256 gasUsed = 100000;
        vm.fee(50 gwei);

        uint256 expectedGasFee = gasUsed * tx.gasprice;
        uint256 expectedTotalFee = INITIAL_FIXED_FEE + expectedGasFee;

        uint256 actualFee = feeRule.calculateFee(user, gasUsed);
        assertEq(actualFee, expectedTotalFee);
    }

    function testCalculateFeeWithGasPriceZeroGasUsed() public view {
        uint256 customGasPrice = 100 gwei;
        uint256 fee = feeRule.calculateFeeWithGasPrice(user, 0, customGasPrice);
        assertEq(fee, INITIAL_FIXED_FEE);
    }

    function testCalculateFeeWithGasPrice() public view {
        uint256 gasUsed = 100000;
        uint256 customGasPrice = 100 gwei;

        uint256 expectedGasFee = gasUsed * customGasPrice;
        uint256 expectedTotalFee = INITIAL_FIXED_FEE + expectedGasFee;

        uint256 actualFee = feeRule.calculateFeeWithGasPrice(user, gasUsed, customGasPrice);
        assertEq(actualFee, expectedTotalFee);
    }

    function testCalculateFeeWithGasPriceVsActualGasPrice() public {
        uint256 gasUsed = 100000;
        uint256 customGasPrice = 100 gwei;
        vm.fee(50 gwei); // Actual gas price different from custom

        uint256 feeWithTxGasPrice = feeRule.calculateFee(user, gasUsed);
        uint256 feeWithCustomGasPrice = feeRule.calculateFeeWithGasPrice(user, gasUsed, customGasPrice);

        // Fee with custom gas price should be different
        assertTrue(feeWithCustomGasPrice != feeWithTxGasPrice);

        // Fee with custom gas price should use the provided price
        uint256 expectedCustomFee = INITIAL_FIXED_FEE + (gasUsed * customGasPrice);
        assertEq(feeWithCustomGasPrice, expectedCustomFee);

        // Fee with tx.gasprice should use the actual price
        uint256 expectedTxFee = INITIAL_FIXED_FEE + (gasUsed * tx.gasprice);
        assertEq(feeWithTxGasPrice, expectedTxFee);
    }

    function testCannotConstructWithZeroFixedFee() public {
        vm.expectRevert(abi.encodeWithSelector(FixedFeeRule.InvalidFixedFee.selector, 0));
        new FixedFeeRule(0);
    }

    function testCalculateFeeWithDifferentGasPrices() public {
        uint256 gasUsed = 100000;
        uint256[] memory gasPrices = new uint256[](3);
        gasPrices[0] = 30 gwei;
        gasPrices[1] = 50 gwei;
        gasPrices[2] = 100 gwei;

        for (uint256 i = 0; i < gasPrices.length; i++) {
            vm.fee(gasPrices[i]);
            uint256 expectedGasFee = gasUsed * tx.gasprice;
            uint256 expectedTotalFee = INITIAL_FIXED_FEE + expectedGasFee;
            uint256 actualFee = feeRule.calculateFee(user, gasUsed);
            assertEq(actualFee, expectedTotalFee);
        }
    }

    function testCalculateFeeWithCustomGasPrices() public view {
        uint256 gasUsed = 100000;
        uint256[] memory customGasPrices = new uint256[](3);
        customGasPrices[0] = 30 gwei;
        customGasPrices[1] = 50 gwei;
        customGasPrices[2] = 100 gwei;

        for (uint256 i = 0; i < customGasPrices.length; i++) {
            uint256 expectedGasFee = gasUsed * customGasPrices[i];
            uint256 expectedTotalFee = INITIAL_FIXED_FEE + expectedGasFee;
            uint256 actualFee = feeRule.calculateFeeWithGasPrice(user, gasUsed, customGasPrices[i]);
            assertEq(actualFee, expectedTotalFee);
        }
    }

    // New test cases for edge cases
    function testCalculateFeeWithMaxGasUsed() public {
        uint256 maxGasUsed = 1_000_000;
        vm.fee(1 gwei);

        uint256 expectedGasFee = maxGasUsed * tx.gasprice;
        uint256 expectedTotalFee = INITIAL_FIXED_FEE + expectedGasFee;

        uint256 actualFee = feeRule.calculateFee(user, maxGasUsed);
        assertEq(actualFee, expectedTotalFee, "Fee calculation incorrect with max gas used");
    }

    function testCalculateFeeWithMaxGasPrice() public {
        uint256 gasUsed = 1000;
        uint256 maxGasPrice = 51 gwei;
        vm.txGasPrice(maxGasPrice);

        uint256 expectedGasFee = gasUsed * maxGasPrice;
        uint256 expectedTotalFee = INITIAL_FIXED_FEE + expectedGasFee;

        uint256 actualFee = feeRule.calculateFee(user, gasUsed);
        assertEq(actualFee, expectedTotalFee, "Fee calculation incorrect with max gas price");
    }

    function testCalculateFeeWithGasPriceMaxGasPrice() public view {
        uint256 gasUsed = 1000;
        uint256 maxGasPrice = 1000 gwei;

        uint256 expectedGasFee = gasUsed * maxGasPrice;
        uint256 expectedTotalFee = INITIAL_FIXED_FEE + expectedGasFee;

        uint256 actualFee = feeRule.calculateFeeWithGasPrice(user, gasUsed, maxGasPrice);
        assertEq(actualFee, expectedTotalFee, "Fee calculation with custom gas price incorrect with max gas price");
    }

    function testCalculateFeeWithZeroAddress() public {
        uint256 gasUsed = 100000;
        vm.fee(50 gwei);

        uint256 expectedGasFee = gasUsed * tx.gasprice;
        uint256 expectedTotalFee = INITIAL_FIXED_FEE + expectedGasFee;

        uint256 actualFee = feeRule.calculateFee(address(0), gasUsed);
        assertEq(actualFee, expectedTotalFee, "Fee calculation incorrect with zero address");
    }

    function testCalculateFeeWithGasPriceZeroAddress() public view {
        uint256 gasUsed = 100000;
        uint256 customGasPrice = 50 gwei;

        uint256 expectedGasFee = gasUsed * customGasPrice;
        uint256 expectedTotalFee = INITIAL_FIXED_FEE + expectedGasFee;

        uint256 actualFee = feeRule.calculateFeeWithGasPrice(address(0), gasUsed, customGasPrice);
        assertEq(actualFee, expectedTotalFee, "Fee calculation with custom gas price incorrect with zero address");
    }

    function testConstructWithMaxValues() public {
        uint256 maxFixedFee = type(uint256).max;

        FixedFeeRule newFeeRule = new FixedFeeRule(maxFixedFee);

        assertEq(newFeeRule.fixedFee(), maxFixedFee, "Failed to set max fixed fee in constructor");
    }
}
