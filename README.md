# 🏛️ On-Chain Dynamic Tax System

> 📈 A Clarity smart contract implementing adaptive fee structures for token transactions

## 🌟 Overview

This project demonstrates an **On-Chain Dynamic Tax System** built with Clarity for the Stacks blockchain. The system implements adaptive tax rates that automatically adjust based on transaction volume, teaching core concepts of dynamic fee structures in DeFi applications.

## ✨ Features

- 🔄 **Dynamic Tax Rates**: Tax rates automatically adjust based on transaction volume
- 📊 **Volume-Based Pricing**: Higher volume periods trigger increased tax rates
- 🏦 **Treasury Management**: Collected taxes are stored in a configurable treasury
- ⚙️ **Admin Controls**: Owner can configure tax parameters and thresholds
- 🔥 **Token Operations**: Full fungible token functionality with mint/burn capabilities
- 📈 **Real-time Monitoring**: View current tax rates and volume metrics

## 🚀 Quick Start

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Basic understanding of Clarity smart contracts

### Installation

1. Clone this repository
2. Navigate to the project directory
3. Run Clarinet commands:

```bash
clarinet check
clarinet test
clarinet console
```

## 🎯 Core Functions

### Public Functions

#### Token Operations
- `mint(amount, recipient)` - 🪙 Mint new tokens (owner only)
- `transfer-with-tax(amount, recipient)` - 💸 Transfer tokens with automatic tax calculation
- `burn(amount)` - 🔥 Burn tokens from sender's balance

#### Admin Functions
- `set-base-tax-rate(rate)` - 📊 Set the base tax rate (in basis points)
- `set-max-tax-rate(rate)` - 🔝 Set maximum tax rate cap
- `set-volume-threshold(threshold)` - 📈 Set volume threshold for rate increases
- `set-treasury(address)` - 🏦 Update treasury address
- `emergency-pause()` - 🚨 Emergency function to maximize tax rate

### Read-Only Functions

- `get-current-tax-rate()` - 📊 Get current dynamic tax rate
- `calculate-tax(amount)` - 🧮 Calculate tax for a given amount
- `get-current-volume()` - 📈 Get current block volume
- `get-total-tax-collected()` - 💰 Get total taxes collected
- `get-balance(account)` - 💳 Get token balance for account

## ⚙️ Configuration

### Default Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Base Tax Rate | 100 (1%) | Minimum tax rate in basis points |
| Max Tax Rate | 1000 (10%) | Maximum tax rate cap |
| Volume Threshold | 1,000,000 | Volume trigger for rate increases |
| Reset Interval | 144 blocks | Volume reset period (~24 hours) |

## 🔧 How It Works

1. **💱 Token Transfer**: User initiates a token transfer
2. **📊 Volume Check**: System checks current transaction volume
3. **🧮 Tax Calculation**: Dynamic tax rate is calculated based on volume
4. **💸 Tax Collection**: Tax is automatically deducted and sent to treasury
5. **📈 Volume Update**: Transaction volume is updated for future calculations
6. **🔄 Reset Logic**: Volume resets periodically to prevent permanent high rates

## 📝 Usage Examples

### Transfer with Tax
```clarity
(contract-call? .on-chain-dynamic-tax-system transfer-with-tax u1000 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

### Check Current Tax Rate
```clarity
(contract-call? .on-chain-dynamic-tax-system get-current-tax-rate)
```

### Set New Base Tax Rate (Owner Only)
```clarity
(contract-call? .on-chain-dynamic-tax-system set-base-tax-rate u200)
```

## 🧪 Testing

Run the test suite with:
```bash
clarinet test
```

The tests cover:
- ✅ Token minting and transfers
- ✅ Dynamic tax rate calculations  
- ✅ Volume-based adjustments
- ✅ Admin function restrictions
- ✅ Edge cases and error handling

## 🛡️ Security Features

- 🔐 **Owner-only functions** for critical operations
- ⚡ **Input validation** on all parameters
- 🚨 **Emergency pause** mechanism
- 💰 **Balance checks** before transfers
- 🔄 **Automatic volume resets** to prevent rate locks

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## 📄 License

This project is open source and available under the MIT License.

---

*Built with ❤️ using Clarity and Clarinet*
