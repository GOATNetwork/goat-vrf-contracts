// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./interfaces/IFeeRule.sol";
import "./interfaces/apro/IAggregatorV3.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20} from
    "../lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @title APROBTCFeeRule
 * @dev Implementation of IFeeRule with a dynamic fee with APRO price feed plus gas cost model.
 *  Please note that this fee rule only supports native token wrapper, if you are using a non-native token as fee token,
 *  it will lead to unexpected behavior.
 */
contract APROBTCFeeRule is IFeeRule {
    // Target value for the fee
    uint256 private immutable _targetValue;
    IAggregatorV3 private immutable _priceFeed;
    uint8 private immutable _priceFeedDecimals;
    ERC20 private immutable _feeToken;
    uint256 private immutable _stalePeriod;

    // Error messages
    error InvalidFee(uint256 target);
    error InvalidPriceFeed(address priceFeed);
    error InvalidFeeToken(address feeToken);
    error InvalidPriceFeedAnswer(uint80 roundId);
    error InvalidTotalDecimals(uint8 decimals);
    error IncompleteRound(uint80 roundId);
    error PriceFeedDecimalsMismatch(uint256 newDecimals, uint256 oldDecimals);
    error InvalidFeeTokenDecimals(uint256 decimals);
    error InvalidStalePeriod(uint256 stalePeriod);
    error PriceOracleStale(uint256 updatedAt, uint256 stalePeriod);

    /**
     * @dev Constructor
     * @param target_ Initial target fee amount in USD
     */
    constructor(uint256 target_, address feeToken_, address priceFeed_, uint256 stalePeriod_) {
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
        uint8 feeTokenDecimals = ERC20(feeToken_).decimals();
        if (feeTokenDecimals != 18) {
            revert InvalidFeeTokenDecimals(feeTokenDecimals);
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

        // These checks are to ensure that the price feed is not manipulated by the oracle
        if (priceFeedDecimals != _priceFeedDecimals) {
            revert PriceFeedDecimalsMismatch(priceFeedDecimals, _priceFeedDecimals);
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
}
