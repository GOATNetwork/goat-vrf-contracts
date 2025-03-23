# GOAT VRF Contracts

GOAT VRF is a decentralized randomness solution that utilizes the [drand network](https://drand.love/) to provide secure, verifiable random values to smart contracts on EVM chains. This service allows developers to integrate reliable randomness into their applications with minimal effort.

## What is GOAT VRF?

GOAT VRF consists of the following components:

- **GoatVRF Contract**: On-chain contract that verifies the randomness proofs and makes them available to consumer contracts.
- **Oracle Service**: Off-chain service that retrieves randomness proofs from the drand network and submits them to the blockchain.
- **Consumer Contracts**: Your contracts that integrate with GoatVRF to request and receive random values.

## Integration Guide

### 1. Smart Contract Integration

To integrate GOAT VRF into your smart contract, implement the `IRandomnessCallback` interface:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MyRandomContract is IRandomnessCallback {
    using SafeERC20 for IERC20;
   
    // GoatVRF contract address
    address public goatVRF;
    
    constructor(address goatVRF_) {
        goatVRF = goatVRF_;
    }

   /**
    * @dev Request randomness from GoatVRF
     * @param maxAllowedGasPrice Maximum allowed gas price for fulfillment
     * @return requestId Unique identifier for the request
     */
   function getNewRandom(uint256 maxAllowedGasPrice) external onlyOwner returns (uint256 requestId) {
      // Get the WGOATBTC token address from GoatVRF
      address tokenAddress = IGoatVRF(goatVRF).feeToken();

      // Calculate fee with sufficient gas for callback
      // The callback is simple, but we allocate extra gas to be safe
      uint256 fee = IGoatVRF(goatVRF).calculateFee(600000);

      // Transfer tokens from caller to this contract if needed
      // This step is optional depending on your token handling strategy

      // Approve GoatVRF to spend tokens
      IERC20 token = IERC20(tokenAddress);
      // Since the underlying token is WGOATBTC (wrapped BTC in GOAT network), and the price is fetched from the price feed oracle in realtime,
      // we need to ensure that the contract has enough allowance for the fee. So it is better to apply a safety margin
      // to avoid any issues with gas price fluctuations. 50% is just a suggested value, you can adjust it as needed.
      // If you do not want to approve the token every time, you can also approve all of your budget at once.
      // Even if you approved the contract with a higher amount, the fee will be calculated based on
      // the gas price at the time of the request and actual usage, so you will not be charged more than the fee.
      uint256 safetyMargin = fee * 3 / 2;
      token.forceApprove(goatVRF, safetyMargin);

      // Get beacon for deadline calculation
      IDrandBeacon beacon = IDrandBeacon(IGoatVRF(goatVRF).beacon());

      // Request randomness with appropriate deadline
      uint256 deadline = block.timestamp + beacon.period();
      requestId = IGoatVRF(goatVRF).getNewRandom(deadline, maxAllowedGasPrice, 600000);
   }
    
    /**
     * @dev Callback function used by GoatVRF to deliver randomness
     * @param requestId Unique identifier for the randomness request
     * @param randomness The random value
     */
    function receiveRandomness(uint256 requestId, uint256 randomness) external override {
        // Only GoatVRF can call this function, make sure you add this check
        require(msg.sender == goatVRF, "Only GoatVRF can fulfill randomness");
        
        // Use randomness in your application
        // For example: selectWinner(randomness);
    }
}

interface IRandomnessCallback {
   function receiveRandomness(uint256 requestId, uint256 randomness) external;
}

interface IDrandBeacon {
   function period() external view returns (uint256);
}

interface IGoatVRF {
   function calculateFee(uint256 gas)
   external
   view
   returns (uint256 totalFee);

   function calculateFeeWithGasPrice(uint256 gas, uint256 gasPrice)
   external
   view
   returns (uint256 totalFee);

   function getNewRandom(uint256 deadline, uint256 maxAllowedGasPrice, uint256 callbackGas)
   external
   returns (uint256 requestId);

   function cancelRequest(uint256 requestId) external;

   function beacon() external view returns (address beaconAddr);

   function feeToken() external view returns (address tokenAddr);
}
```

### 2. How GOAT VRF Works

1. Your contract calls `requestRandomness()` on the GoatVRF contract, providing:
   - A deadline by which the randomness must be fulfilled
   - A maximum gas price you're willing to pay for the callback
   - A gas limit for your callback function

2. The GoatVRF contract collects a fee in $WGOATBTC tokens to cover gas costs.

3. The off-chain Oracle service monitors the chain for randomness requests and submits proofs from the drand network.

4. When a valid proof is submitted, GoatVRF calls your contract's `receiveRandomness()` function with the resulting random value.

### 3. Implementation Details

#### Fee Calculation

The fee for randomness requests is calculated based on the gas limit for your callback:

```solidity
// Calculate fee with sufficient gas and current tx.gasprice for callback
uint256 fee = IGoatVRF(goatVRF).calculateFee(600000);

// Calculate fee with sufficient gas and desired gas price for callback
uint256 fee = IGoatVRF(goatVRF).calculateFeeWithGasPrice(600000, 0.01 gwei);
```

#### Token Approval

Before requesting randomness, you must approve the GoatVRF contract to spend your WGOATBTC tokens:

```solidity
// Get token address
address tokenAddress = IGoatVRF(goatVRF).feeToken();
IERC20 token = IERC20(tokenAddress);

// Approve fee
require(token.approve(goatVRF, fee), "Token approval failed");
```

#### Setting Appropriate Deadline

Use the drand beacon's period to calculate a reasonable deadline:

```solidity
IDrandBeacon beacon = IDrandBeacon(IGoatVRF(goatVRF).beacon());
uint256 deadline = block.timestamp + beacon.period();
```

## Building and Testing

This project uses [Foundry](https://book.getfoundry.sh/) for development:

```shell
# Build contracts
forge build

# Run tests
forge test

# Deploy contracts
forge script script/Deploy.s.sol --rpc-url <your_rpc_url> --private-key <your_private_key>
```

## Fee Rule Types

GOAT VRF supports two types of fee rules:

1. **Fixed Fee Rule**: A simple fixed fee plus gas cost model.
   - Configuration: Set `FEE_RULE_TYPE=FIXED` and `FIXED_FEE=amount` in your environment.

2. **APRO BTC Fee Rule**: A dynamic fee model based on APRO price feed for BTC/USD.
   - Configuration: Set `FEE_RULE_TYPE=APRO_BTC`, `TARGET_VALUE=amount` (in USD with 8 decimals), and `PRICE_FEED=address` in your environment.
   - This allows the fee to adjust automatically based on the current BTC price to maintain a consistent USD value.

## Contract Deployments

- **Testnet**: 

| Property              | Value                                                         |
|-----------------------|---------------------------------------------------------------|
| Fee Token             | 0xbC10000000000000000000000000000000000000                     |
| Beacon Type           | BN254                                                         |
| Beacon                | 0x9a9d4bEB5331C8Cb493ab2D9906601cDC0e3C804                     |
| Fee Rule Type         | APRO_BTC                                                      |
| Fee Rule              | 0x9D5824306D1F35Bf45C8Cae2591D24b6ca8B5e80                     |
| Target Value          | 10000000                                                      |
| Price Feed            | 0x0c98A1AAECE12D6815A02fD2A6d24652325FD6Ef                     |
| Fee Recipient         | 0xF51d148D4A7ae851c1d5641763081023938c6342                     |
| Relayer               | 0x5C71d12522c454689A6A1653A99A44Bd5Fa4A65B                     |
| Overhead Gas          | 200000                                                        |
| Max Deadline Delta    | 604800                                                        |
| Request Expire Time   | 604800                                                        |
| GoatVRF Proxy         | 0xeccdB88d82eeC273cA6c305046cB6ac14D7B007c                     |

- **Mainnet**: `TBD`

## Further Information

For more examples and detailed documentation, see the [examples](./src/examples/) directory and [interfaces](./src/interfaces/) directory.