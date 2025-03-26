// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/**
 * @title IFeeRule
 * @dev Interface for fee calculation rules
 */
interface IFeeRule {
    /**
     * @dev Calculate the fee for a randomness request
     * @param requester Address of the requester
     * @param gasUsed Amount of gas used
     * @return fee Total fee for the request
     */
    function calculateFee(address requester, uint256 gasUsed) external view returns (uint256 fee);

    /**
     * @dev Calculate the fee for a randomness request with custom gas price
     * @param requester Address of the requester
     * @param gasUsed Amount of gas used
     * @param gasPrice Custom gas price for the calculation
     * @return fee Total fee for the request
     */
    function calculateFeeWithGasPrice(address requester, uint256 gasUsed, uint256 gasPrice)
        external
        view
        returns (uint256 fee);
}
