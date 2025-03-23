// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IFeeRule.sol";
import "./interfaces/apro/IAggregatorV3.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title APROBTCFeeRule
 * @dev Implementation of IFeeRule with a dynamic fee with APRO price feed plus gas cost model
 */
contract APROBTCFeeRule is Ownable, IFeeRule {
    // Target value for the fee
    uint256 private _targetValue;
    IAggregatorV3 private _priceFeed;
    uint8 private _priceFeedDecimals;
    ERC20 private _feeToken;
    uint256 private _stalePeriod;

    // Events
    event FeeUpdated(uint256 newTarget);
    event PriceFeedUpdated(address newPriceFeed);
    event FeeTokenUpdated(address newFeeToken);

    // Error messages
    error InvalidFee(uint256 target);
    error InvalidPriceFeed(address priceFeed);
    error InvalidFeeToken(address feeToken);
    error InvalidPriceFeedAnswer(uint80 roundId);
    error InvalidTotalDecimals(uint8 decimals);
    error IncompleteRound(uint80 roundId);
    error PriceFeedDecimalsMismatch(uint256 newDecimals, uint256 oldDecimals);
    error InvalidStalePeriod(uint256 stalePeriod);
    error PriceOracleStale(uint256 updatedAt, uint256 stalePeriod);

    /**
     * @dev Constructor
     * @param target_ Initial target fee amount in USD
     */
    constructor(uint256 target_, address feeToken_, address priceFeed_, uint256 stalePeriod_) Ownable(msg.sender) {
        if (target_ == 0) {
            revert InvalidFee(target_);
        }
        if (priceFeed_ == address(0)) {
            revert InvalidPriceFeed(priceFeed_);
        }
        if (feeToken_ == address(0)) {
            revert InvalidFeeToken(feeToken_);
        }
        if (stalePeriod_ == 0) {
            revert InvalidStalePeriod(stalePeriod_);
        }

        _stalePeriod = stalePeriod_;
        _targetValue = target_;
        _priceFeed = IAggregatorV3(priceFeed_);
        _feeToken = ERC20(feeToken_);

        uint8 priceFeedDecimals = _priceFeed.decimals();
        if (priceFeedDecimals == 0) {
            revert InvalidPriceFeed(priceFeed_);
        }

        _priceFeedDecimals = priceFeedDecimals;

        emit FeeUpdated(target_);
        emit PriceFeedUpdated(address(priceFeed_));
        emit FeeTokenUpdated(address(_feeToken));
    }

    /**
     * @dev Calculate the fee for a randomness request
     * @param gasUsed Amount of gas used
     * @return fee Total fee for the request
     */
    function calculateFee(address, uint256 gasUsed) external view override returns (uint256 fee) {
        return calculateFeeWithGasPrice(address(0), gasUsed, tx.gasprice);
    }

    /**
     * @dev Calculate the fee for a randomness request with custom gas price
     * @param gasUsed Amount of gas used
     * @param gasPrice Custom gas price for calculation
     * @return fee Total fee for the request
     */
    function calculateFeeWithGasPrice(address, uint256 gasUsed, uint256 gasPrice)
        public
        view
        override
        returns (uint256 fee)
    {
        (uint80 roundId, int256 feeTokenPrice,, uint256 updatedAt,) = _priceFeed.latestRoundData();
        uint8 feeTokenDecimals = _feeToken.decimals();
        uint8 priceFeedDecimals = _priceFeed.decimals();
        uint8 savedPriceFeedDecimals = _priceFeedDecimals;

        // These checks are to ensure that the price feed is not manipulated by the oracle
        if (priceFeedDecimals != savedPriceFeedDecimals) {
            revert PriceFeedDecimalsMismatch(priceFeedDecimals, savedPriceFeedDecimals);
        }

        if (feeTokenPrice <= 0) {
            revert InvalidPriceFeedAnswer(roundId);
        }

        if (updatedAt == 0) {
            revert IncompleteRound(roundId);
        }

        if (block.timestamp - updatedAt > _stalePeriod) {
            revert PriceOracleStale(updatedAt, block.timestamp - updatedAt);
        }

        // avoid overflow in fee calculation
        uint8 totalDecimals = priceFeedDecimals + feeTokenDecimals;
        if (totalDecimals > 77) {
            revert InvalidTotalDecimals(totalDecimals);
        }

        uint256 _fixedFee = (_targetValue * (10 ** feeTokenDecimals)) / uint256(feeTokenPrice);

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
    function targetValue() external view returns (uint256) {
        return _targetValue;
    }

    /**
     * @dev Get the current price feed usd decimals
     * @return The price feed decimals for usd
     */
    function decimals() external view returns (uint8) {
        return _priceFeedDecimals;
    }

    /**
     * @dev Get the current price feed
     * @return The price feed address
     */
    function priceFeed() external view returns (address) {
        return address(_priceFeed);
    }

    /**
     * @dev Get the current fee token
     * @return The fee token address
     */
    function feeToken() external view returns (address) {
        return address(_feeToken);
    }

    /**
     * @dev Get the current stale period
     * @return The stale period in seconds
     */
    function stalePeriod() external view returns (uint256) {
        return _stalePeriod;
    }

    /**
     * @dev Set the target value
     * @param target_ The new target value
     */
    function setTargetValue(uint256 target_) external onlyOwner {
        if (target_ == 0) {
            revert InvalidFee(target_);
        }
        _targetValue = target_;
        emit FeeUpdated(target_);
    }

    /**
     * @dev Set the price feed
     * @param priceFeed_ The new price feed
     */
    function setPriceFeed(address priceFeed_) external onlyOwner {
        if (priceFeed_ == address(0)) {
            revert InvalidPriceFeed(priceFeed_);
        }
        _priceFeed = IAggregatorV3(priceFeed_);
        uint256 priceFeedDecimals = _priceFeed.decimals();
        if (priceFeedDecimals == 0) {
            revert InvalidPriceFeed(priceFeed_);
        }

        emit PriceFeedUpdated(priceFeed_);
    }

    /**
     * @dev Set the fee token
     * @param feeToken_ The new fee token
     */
    function setFeeToken(address feeToken_) external onlyOwner {
        if (feeToken_ == address(0)) {
            revert InvalidFeeToken(feeToken_);
        }
        _feeToken = ERC20(feeToken_);
        emit FeeTokenUpdated(feeToken_);
    }

    /**
     * @dev Set the stale period
     * @param stalePeriod_ The new stale period
     */
    function setStalePeriod(uint256 stalePeriod_) external onlyOwner {
        if (stalePeriod_ == 0) {
            revert InvalidStalePeriod(stalePeriod_);
        }
        _stalePeriod = stalePeriod_;
    }
}
