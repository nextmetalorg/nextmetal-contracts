# Presale Contract Specifications

## Overview
The Presale contract is a token presale management system that handles multiple funding rounds with different pricing tiers, allocation limits, and access controls.

## Setup

After cloning the repo, run:

```bash
make setup
```

## Key Features

### Token Configuration
- **Total Supply Cap**: 500,000,000 tokens (with 18 decimals)
- **Token Standard**: ERC20-like balance tracking without transfer functionality
- **Payment Currency**: USDC (6 decimals)

### Funding Rounds
The contract supports 4 distinct rounds:

| Round | ID | Allocation | Price per Token | Total Raise Potential |
|-------|----|-----------:|----------------:|----------------------:|
| Angel | 0 | 5M tokens | $0.05 USDC | $250,000 |
| Seed | 1 | 5M tokens | $0.10 USDC | $500,000 |
| VC | 2 | 10M tokens | $0.18 USDC | $1,800,000 |
| Community | 3 | 10M tokens | $0.50 ~ $1.0 USDC | $5,000,000 |

### Round Management
- **Activation Control**: Owner can start/stop rounds independently
- **Whitelist Support**: Optional whitelist enforcement per round
- **Purchase Limits**: Configurable min/max purchase amounts per round
- **Partial Fills**: Automatic adjustment when purchase exceeds available allocation

### Access Control
- **Owner Functions**: Round management, whitelist control, purchase limits, treasury updates
- **Pausable**: Contract-wide pause mechanism for emergency stops
- **Treasury**: Dedicated address for receiving USDC payments

### Safety Features
- **Overflow Protection**: Automatic token amount calculation with remainder handling
- **Per-Wallet Limits**: Track cumulative purchases per round per address
- **Input Validation**: Zero address checks, round ID validation
- **State Guards**: Active round checks, whitelist verification

### Events
- Purchase tracking with round ID, buyer, USDC amount, and token amount
- Round lifecycle events (started/stopped)
- Whitelist management events
- Treasury updates and pause state changes

### Error Handling
Custom errors for better gas efficiency:
- `InvalidRound`, `RoundNotActive`, `NotWhitelisted`
- `BelowMinimumPurchase`, `ExceedsMaximumPurchase`
- `ContractPaused`, `InvalidAddress`

## Integration Points
For frontend usage examples, see [docs/integration.md](docs/integration.md).

- **Dependencies**: Solady library for Ownable and SafeTransferLib
- **External Calls**: USDC transfers via SafeTransferLib
- **View Functions**: `getRoundInfo()` for comprehensive round data retrieval


## Deployment

The project includes a simple deployment script located at `script/Deploy.s.sol`.
Set the following environment variables and run the script with `forge script`:


```bash

forge clean && forge build

forge test

forge script script/Deploy.s.sol \
     --broadcast \
     --rpc-url $SEPOLIA_RPC_URL \
     --verify \
     --etherscan-api-key $ETHERSCAN_API_KEY \
     --private-key $PRIVATE_METAL \
     --chain-id $CHAIN_ID

cast send 0x3ce78378F6fcdAA8F17e82745bEfE5352a4Ce385 "startRound(uint8)" 3 \
     --private-key $PRIVATE_METAL --rpc-url $SEPOLIA_URL --chain sepolia


forge script script/Deploy.s.sol \
     --broadcast \
     --rpc-url $MAINNET_URL \
     --verify \
     --etherscan-api-key $ETHERSCAN_API_KEY \
     --private-key $PRIVATE_METAL

cast send 0x3ce78378F6fcdAA8F17e82745bEfE5352a4Ce385 "startRound(uint8)" 0 \
     --private-key $PRIVATE_METAL --rpc-url $MAINNET_URL --chain mainnet

cast call \
  --from $(cast wallet address --private-key $PRIVATE_METAL) \
  --rpc-url $MAINNET_URL \
  0x3ce78378F6fcdAA8F17e82745bEfE5352a4Ce385 \
  "startRound(uint8)" 0

cast send 0x3ce78378F6fcdAA8F17e82745bEfE5352a4Ce385 \
  "startRound(uint8)" 0 \
  --private-key $PRIVATE_METAL \
  --rpc-url $MAINNET_URL

```

This deploys the `Presale` contract using the specified parameters.
