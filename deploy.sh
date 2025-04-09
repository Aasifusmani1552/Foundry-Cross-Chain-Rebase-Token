#!/bin/bash

# Define constants
AMOUNT=100000

# Default ZKsync and Sepolia Keys and Addresses
DEFAULT_ZKSYNC_LOCAL_KEY="0x7726827caac94a7f9e1b160f7ea819f172f7b6f9d2a97f992c38edeab82d4110"
DEFAULT_ZKSYNC_ADDRESS="0x36615Cf349d7F6344891B1e7CA7C72883F5dc049"

ZKSYNC_REGISTRY_MODULE_OWNER_CUSTOM="0x3139687Ee9938422F57933C3CDB3E21EE43c4d0F"
ZKSYNC_TOKEN_ADMIN_REGISTRY="0xc7777f12258014866c677Bdb679D0b007405b7DF"
ZKSYNC_ROUTER="0xA1fdA8aa9A8C4b945C45aD30647b01f07D7A0B16"
ZKSYNC_RNM_PROXY_ADDRESS="0x3DA20FD3D8a8f8c1f1A5fD03648147143608C467"
ZKSYNC_SEPOLIA_CHAIN_SELECTOR="6898391096552792247"
ZKSYNC_LINK_ADDRESS="0x23A1aFD896c8c8876AF46aDc38521f4432658d1e"

SEPOLIA_REGISTRY_MODULE_OWNER_CUSTOM="0x62e731218d0D47305aba2BE3751E7EE9E5520790"
SEPOLIA_TOKEN_ADMIN_REGISTRY="0x95F29FEE11c5C55d26cCcf1DB6772DE953B37B82"
SEPOLIA_ROUTER="0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59"
SEPOLIA_RNM_PROXY_ADDRESS="0xba3f6251de62dED61Ff98590cB2fDf6871FbB991"
SEPOLIA_CHAIN_SELECTOR="16015286601757825753"
SEPOLIA_LINK_ADDRESS="0x779877A7B0D9E8603169DdbD7836e478b4624789"

# Load environment variables
source .env

# Function to handle errors and exit
handle_error() {
    echo "Error: $1"
    exit 1
}

# Function to deploy contract and handle output
deploy_contract() {
    local contract_name="$1"
    local constructor_args="$2" # Added constructor args
    local rpc_url="$3"
    local account="$4"
    local zksync_flag="$5" # Added zksync flag

    local command="forge create src/$contract_name.sol:$contract_name --rpc-url $rpc_url --account $account --legacy"
    if [ "$zksync_flag" = "true" ]; then
        command="$command --zksync"
    fi
    if [ -n "$constructor_args" ]; then # Added constructor args
      command="$command --constructor-args $constructor_args"
    fi

    echo "Deploying $contract_name on $rpc_url..."
    local output=$($command 2>&1) # Capture both stdout and stderr
    local address=$(echo "$output" | grep 'Deployed to:' | awk '{print $3}')

    if [ -z "$address" ]; then
        echo "Deployment output: $output" # Print full output for debugging
        handle_error "Failed to deploy $contract_name"
    fi
    echo "$contract_name address: $address"
    echo "Deployment output: $output" # print
    echo $address
}

# 1. Deploy on ZKsync Sepolia

# Compile contracts
forge build --zksync || handle_error "Failed to compile contracts"

# Deploy Rebase Token on ZKsync
ZKSYNC_REBASE_TOKEN_ADDRESS=$(deploy_contract "RebaseToken" "" "${ZKSYNC_SEPOLIA_RPC_URL}" "your account" "true") || handle_error "Failed to deploy RebaseToken on ZKsync"

# Deploy Pool on ZKsync, pass the rebase token address
ZKSYNC_POOL_ADDRESS=$(deploy_contract "RebaseTokenPool" "$ZKSYNC_REBASE_TOKEN_ADDRESS [] ${ZKSYNC_RNM_PROXY_ADDRESS} ${ZKSYNC_ROUTER}" "${ZKSYNC_SEPOLIA_RPC_URL}" "your account" "true") || handle_error "Failed to deploy RebaseTokenPool on ZKsync"

# Set pool permissions.  Added error handling.
echo "Setting the permissions for the pool contract on ZKsync..."
if ! cast send ${ZKSYNC_REBASE_TOKEN_ADDRESS} --rpc-url ${ZKSYNC_SEPOLIA_RPC_URL} --account your account "grantMintAndBurnRole(address)" ${ZKSYNC_POOL_ADDRESS} --legacy; then
  handle_error "Failed to set pool permissions"
fi
echo "Pool permissions set"

# Set CCIP roles and permissions.  Added error handling.
echo "Setting the CCIP roles and permissions on ZKsync..."
if ! cast send ${ZKSYNC_REGISTRY_MODULE_OWNER_CUSTOM} "registerAdminViaOwner(address)" ${ZKSYNC_REBASE_TOKEN_ADDRESS} --rpc-url ${ZKSYNC_SEPOLIA_RPC_URL} --account your account; then
  handle_error "Failed to register admin"
fi
if ! cast send ${ZKSYNC_TOKEN_ADMIN_REGISTRY} "acceptAdminRole(address)" ${ZKSYNC_REBASE_TOKEN_ADDRESS} --rpc-url ${ZKSYNC_SEPOLIA_RPC_URL} --account your account; then
  handle_error "Failed to accept admin role"
fi

if ! cast send ${ZKSYNC_TOKEN_ADMIN_REGISTRY} "setPool(address,address)" ${ZKSYNC_REBASE_TOKEN_ADDRESS} ${ZKSYNC_POOL_ADDRESS} --rpc-url ${ZKSYNC_SEPOLIA_RPC_URL} --account your account; then
  handle_error "Failed to set pool"
fi
echo "CCIP roles and permissions set"

# 2. Deploy on Sepolia

echo "Running the script to deploy the contracts on Sepolia..."
output=$(forge script ./script/Deployer.s.sol:TokenAndPoolDeployer --rpc-url ${SEPOLIA_RPC_URL} --account your account --broadcast 2>&1) # Capture stderr
if [[ $output == *"Error:"* ]]; then
    echo "$output"
    handle_error "Failed to deploy contracts on Sepolia"
fi
echo "Contracts deployed and permission set on Sepolia"

# Extract the addresses from the output
SEPOLIA_REBASE_TOKEN_ADDRESS=$(echo "$output" | grep 'token: contract RebaseToken' | awk '{print $4}')
SEPOLIA_POOL_ADDRESS=$(echo "$output" | grep 'pool: contract RebaseTokenPool' | awk '{print $4}')

echo "Sepolia rebase token address: $SEPOLIA_REBASE_TOKEN_ADDRESS"
echo "Sepolia pool address: $SEPOLIA_POOL_ADDRESS"

# Deploy the vault
echo "Deploying the vault on Sepolia..."
VAULT_ADDRESS=$(forge script ./script/Deployer.s.sol:VaultDeployer --rpc-url ${SEPOLIA_RPC_URL} --account your account --broadcast --sig "run(address)" ${SEPOLIA_REBASE_TOKEN_ADDRESS} 2>&1 | grep 'vault: contract Vault' | awk '{print $NF}') # Capture stderr
if [ -z "$VAULT_ADDRESS" ]; then
  handle_error "Failed to deploy Vault"
fi
echo "Vault address: $VAULT_ADDRESS"

# Configure the pool on Sepolia
echo "Configuring the pool on Sepolia..."
if ! forge script ./script/ConfigurePool.s.sol:ConfigurePoolScript --rpc-url ${SEPOLIA_RPC_URL} --account your account --broadcast --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" ${SEPOLIA_POOL_ADDRESS} ${ZKSYNC_SEPOLIA_CHAIN_SELECTOR} ${ZKSYNC_POOL_ADDRESS} ${ZKSYNC_REBASE_TOKEN_ADDRESS} false 0 0 false 0 0; then
  handle_error "Failed to configure pool on Sepolia"
fi

# Deposit funds to the vault
echo "Depositing funds to the vault on Sepolia..."
if ! cast send ${VAULT_ADDRESS} --value ${AMOUNT} --rpc-url ${SEPOLIA_RPC_URL} --account your account "deposit()"; then
  handle_error "Failed to deposit to vault"
fi

# Wait a beat for some interest to accrue

# Configure the pool on ZKsync
echo "Configuring the pool on ZKsync..."
if ! cast send ${ZKSYNC_POOL_ADDRESS}  --rpc-url ${ZKSYNC_SEPOLIA_RPC_URL} --account your account "applyChainUpdates(uint64[],(uint64,bytes[],bytes,(bool,uint128,uint128),(bool,uint128,uint128))[])" "[${SEPOLIA_CHAIN_SELECTOR}]" "[(${SEPOLIA_CHAIN_SELECTOR},[$(cast abi-encode \"f(address)\" ${SEPOLIA_POOL_ADDRESS})],$(cast abi-encode \"f(address)\" ${SEPOLIA_REBASE_TOKEN_ADDRESS}),(false,0,0),(false,0,0))]"; then
  handle_error "Failed to configure pool on ZKsync"
fi

# Bridge the funds using the script to zksync
echo "Bridging the funds using the script to ZKsync..."
SEPOLIA_BALANCE_BEFORE=$(cast balance $(cast wallet address --account your account) --erc20 ${SEPOLIA_REBASE_TOKEN_ADDRESS} --rpc-url ${SEPOLIA_RPC_URL})
echo "Sepolia balance before bridging: $SEPOLIA_BALANCE_BEFORE"
if ! forge script ./script/BridgeTokens.s.sol:BridgeTokensScript --rpc-url ${SEPOLIA_RPC_URL} --account your account --broadcast --sig "run(address,uint64,address,uint256,address,address)" $(cast wallet address --account your account) ${ZKSYNC_SEPOLIA_CHAIN_SELECTOR} ${SEPOLIA_REBASE_TOKEN_ADDRESS} ${AMOUNT} ${SEPOLIA_LINK_ADDRESS} ${SEPOLIA_ROUTER}; then
   handle_error "Failed to bridge tokens"
fi
echo "Funds bridged to ZKsync"
SEPOLIA_BALANCE_AFTER=$(cast balance $(cast wallet address --account your account) --erc20 ${SEPOLIA_REBASE_TOKEN_ADDRESS} --rpc-url ${SEPOLIA_RPC_URL})
echo "Sepolia balance after bridging: $SEPOLIA_BALANCE_AFTER"
