# 🌉 Multi-Derivative Asset Gateway

> Bridge your Ethereum assets to Stacks with seamless token representations 

## 📋 Overview

The Multi-Derivative Asset Gateway enables users to deposit ERC-20 tokens on Ethereum and mint corresponding derivative tokens on the Stacks blockchain. This cross-chain bridge maintains a 1:1 backing ratio and provides secure asset management through oracle-based verification.

## ✨ Features

- 🔒 **Secure Deposits**: Track Ethereum deposits with transaction hash verification
- 🪙 **Token Minting**: Mint 1:1 backed derivative tokens on Stacks
- 🔥 **Token Burning**: Burn derivative tokens to initiate withdrawals
- 📊 **Multi-Token Support**: Support for multiple ERC-20 tokens
- 🔐 **Oracle Management**: Authorized oracles for deposit verification
- ⏸️ **Emergency Controls**: Pause/unpause functionality for security
- 💸 **Token Transfers**: Transfer derivative tokens between users

## 🚀 Quick Start

### Prerequisites
- Clarinet installed
- Node.js for testing
- Access to Ethereum network for deposits

### Installation

1. Clone the repository
2. Navigate to project directory
3. Run Clarinet check to validate contracts

```bash
clarinet check
```

## 📖 Usage Guide

### 🏗️ Contract Deployment

Deploy the contract and set up initial configuration:

```clarity
;; Contract deploys with deployer as owner
```

### 🔧 Admin Functions

#### Register New Token
```clarity
(contract-call? .multi-derivative-gateway register-token 
  0x... ;; token contract address (20 bytes)
  "TokenName" ;; token name
  "TKN" ;; token symbol
  u18) ;; decimals
```

#### Add Oracle
```clarity
(contract-call? .multi-derivative-gateway add-oracle 'ST1ORACLE...)
```

#### Pause Contract (Emergency)
```clarity
(contract-call? .multi-derivative-gateway pause-contract)
```

### 🌐 Oracle Functions

#### Record Ethereum Deposit
```clarity
(contract-call? .multi-derivative-gateway record-deposit
  0x... ;; ethereum address (20 bytes)
  'ST1RECIPIENT... ;; stacks recipient
  0x... ;; token contract (20 bytes)
  u1000000 ;; amount
  u12345 ;; ethereum block height
  0x...) ;; transaction hash (32 bytes)
```

#### Mint Derivative Tokens
```clarity
(contract-call? .multi-derivative-gateway mint-derivative-token u1)
```

### 👤 User Functions

#### Check Balance
```clarity
(contract-call? .multi-derivative-gateway get-balance 
  'ST1USER... 
  0x...)
```

#### Transfer Tokens
```clarity
(contract-call? .multi-derivative-gateway transfer
  'ST1RECIPIENT...
  0x... ;; token contract
  u100) ;; amount
```

#### Burn Tokens (Initiate Withdrawal)
```clarity
(contract-call? .multi-derivative-gateway burn-derivative-token
  0x... ;; token contract
  u100 ;; amount to burn
  0x...) ;; ethereum recipient address
```

### 📊 Query Functions

#### Get Deposit Information
```clarity
(contract-call? .multi-derivative-gateway get-deposit-info u1)
```

#### Get Token Information
```clarity
(contract-call? .multi-derivative-gateway get-token-info 0x...)
```

#### Check Oracle Authorization
```clarity
(contract-call? .multi-derivative-gateway is-oracle-authorized 'ST1ORACLE...)
```

## 🔄 Workflow

### 💰 Deposit to Mint Flow
1. User deposits ERC-20 tokens to Ethereum bridge contract
2. Oracle detects deposit and calls `record-deposit`
3. Oracle calls `mint-derivative-token` to mint Stacks tokens
4. User receives derivative tokens on Stacks

### 🔥 Burn to Withdraw Flow
1. User calls `burn-derivative-token` with withdrawal details
2. Burn event is emitted with Ethereum recipient address
3. Oracle processes burn and initiates Ethereum withdrawal
4. User receives original tokens on Ethereum

## ⚡ Error Codes

- `u100` - Owner only operation
- `u101` - Not authorized (oracle required)
- `u102` - Invalid amount (must be > 0)
- `u103` - Insufficient balance
- `u104` - Deposit not found
- `u105` - Already minted
- `u106` - Invalid address
- `u107` - Token not found or inactive
- `u108` - Contract paused

## 🛡️ Security Features

- **Owner Controls**: Critical functions restricted to contract owner
- **Oracle System**: Authorized oracles verify cross-chain transactions
- **Pause Mechanism**: Emergency pause for security incidents
- **Duplicate Protection**: Prevents double-minting of deposits
- **Balance Tracking**: Accurate balance management with overflow protection

## 🏗️ Architecture

### Data Structures

- **deposits**: Maps deposit IDs to deposit information
- **ethereum-deposits**: Maps Ethereum tx hash + token to deposit ID
- **user-balances**: Maps user + token to balance
- **token-info**: Maps token contract to metadata
- **authorized-oracles**: Maps principals to authorization status

### Key Functions

- `record-deposit`: Records new Ethereum deposit
- `mint-derivative-token`: Mints backed tokens on Stacks
- `burn-derivative-token`: Burns tokens for withdrawal
- `transfer`: Transfers tokens between users

## 📝 Testing

Run the test suite:

```bash
clarinet test
```

## 🤝 Contributing

1. Fork the repository
2. Create feature branch
3. Add tests for new functionality
4. Submit pull request

## 📄 License

MIT License - see LICENSE file for details

## 🔗 Links

- [Stacks Documentation](https://docs.stacks.co/)
- [Clarity Language Reference](https://docs.stacks.co/clarity/)
- [Clarinet Documentation](https://github.com/hirosystems/clarinet)

---

*Built with ❤️ for the Stacks ecosystem*

# Multi-Derivative Asset Gateway

