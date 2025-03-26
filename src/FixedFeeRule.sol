// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./interfaces/IFeeRule.sol";

/**
 * @title FixedFeeRule
 * @dev Implementation of IFeeRule with a fixed fee plus gas cost model
 */
contract FixedFeeRule is IFeeRule {
    // Fixed fee amount
    uint256 private immutable _fixedFee;

    // Error messages
    error InvalidFixedFee(uint256 fixedFee);

    /**
     * @dev Constructor
     * @param fixedFee_ Initial fixed fee amount
     */
    constructor(uint256 fixedFee_) {
        if (fixedFee_ == 0) {
            revert InvalidFixedFee(fixedFee_);
        }

        _fixedFee = fixedFee_;
    }

    /**
     * @dev Calculate the fee for a randomness request
     * @param gasUsed Amount of gas used
     * @return fee Total fee for the request
     */
    function calculateFee(address, uint256 gasUsed) external view override returns (uint256 fee) {
        // Return fixed fee for pre-calculation
        if (gasUsed == 0) {
            return _fixedFee;
        }

        // Calculate gas fee
        uint256 gasFee = gasUsed * tx.gasprice;

        // Total fee = fixed fee + gas fee
        return _fixedFee + gasFee;
    }

    /**
     * @dev Calculate the fee for a randomness request with custom gas price
     * @param gasUsed Amount of gas used
     * @param gasPrice Custom gas price for calculation
     * @return fee Total fee for the request
     */
    function calculateFeeWithGasPrice(address, uint256 gasUsed, uint256 gasPrice)
        external
        view
        override
        returns (uint256 fee)
    {
        // Return fixed fee for pre-calculation
        if (gasUsed == 0) {
            return _fixedFee;
        }

        // Calculate gas fee with the provided gas price
        uint256 gasFee = gasUsed * gasPrice;

        // Total fee = fixed fee + gas fee
        return _fixedFee + gasFee;
    }

    /**
     * @dev Get the current fixed fee
     * @return The fixed fee
     */
    function fixedFee() external view returns (uint256) {
        return _fixedFee;
    }
}
