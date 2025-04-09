# 🌐 Cross-Chain Rebase Token

This repository contains the implementation of a **Cross-Chain Rebase Token** – a special ERC-20 compatible token with automatic rebasing mechanics and support for transferring balances across chains.

## 🧠 Overview

The token features:
- 📈 **Rebasing Logic**: A modified `balanceOf` function that returns the user's balance including **accrued interest** over time.
- 🌉 **Cross-Chain Compatibility**: Enables token data and state to be communicated between chains using supporting contracts and configurations.
- ⚙️ **Deployment Scripts**: Includes Foundry scripts for contract deployment and cross-chain bridging setup.
- 🖥️ **Bash Scripts**: Two helper bash scripts demonstrate deployment and bridging from Sepolia to zkSync.

## 🧩 Components

- `RebaseToken.sol`: Main ERC-20 token with rebasing logic in `balanceOf`.
- Supporting contracts for cross-chain messaging and configuration.
- `Deployer.s.sol`: Script to deploy contracts on different chains.
- `BridgeTokens.s.sol`: Script to initiate bridging between networks.
- `bridgeToZksync.sh`: Deploys and configures contracts on Sepolia and zkSync testnets.
- `deploy.sh`: Another script if the first one not works

## ⚠️ Important Notice

> The provided scripts (`.sh`) **may not work out-of-the-box** on testnets due to dependencies, timing issues, or environment differences.  
> They are intended as a **reference** to understand the deployment flow, configuration patterns, and bridging logic.

## 🛠️ Setup

1. Install [Foundry](https://book.getfoundry.sh/getting-started/installation) and ensure you're on the latest version.
2. Clone the repository and run:
   ```bash
   forge install
