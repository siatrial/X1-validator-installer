#!/bin/bash

# Function to print color-coded messages
function print_color {
    case $1 in
        "info")
            echo -e "\033[1;34m$2\033[0m"  # Blue for informational
            ;;
        "success")
            echo -e "\033[1;32m$2\033[0m"  # Green for success
            ;;
        "error")
            echo -e "\033[1;31m$2\033[0m"  # Red for errors
            ;;
        "prompt")
            echo -e "\033[1;33m$2\033[0m"  # Yellow for user prompts
            ;;
    esac
}

# Section 1: Setup Validator Directory
print_color "info" "\n===== 1/10: Validator Directory Setup ====="

default_install_dir="$HOME/x1_validator"
print_color "prompt" "Validator Directory (press Enter for default: $default_install_dir):"
read install_dir

if [ -z "$install_dir" ]; then
    install_dir=$default_install_dir
fi

if [ -d "$install_dir" ]; then
    print_color "prompt" "Directory exists. Delete it? [y/n]"
    read choice
    if [ "$choice" == "y" ]; then
        rm -rf "$install_dir" > /dev/null 2>&1
        print_color "info" "Deleted $install_dir"
    else
        print_color "error" "Please choose a different directory."
        exit 1
    fi
fi

mkdir -p "$install_dir" > /dev/null 2>&1
cd "$install_dir" || exit 1
print_color "success" "Directory created: $install_dir"

# Section 2: Install Rust
print_color "info" "\n===== 2/10: Rust Installation ====="

if ! command -v rustc &> /dev/null; then
    print_color "info" "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y > /dev/null 2>&1
    . "$HOME/.cargo/env" > /dev/null 2>&1
else
    print_color "success" "Rust is already installed: $(rustc --version)"
fi
print_color "success" "Rust installed."

# Section 3: Install Solana CLI
print_color "info" "\n===== 3/10: Solana CLI Installation ====="

print_color "info" "Installing Solana CLI..."
sh -c "$(curl -sSfL https://release.solana.com/v1.18.25/install)" > /dev/null 2>&1 || {
    print_color "error" "Solana CLI installation failed."
    exit 1
}

# Add Solana to PATH and reload
if ! grep -q 'solana' ~/.profile; then
    echo 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' >> ~/.profile
fi
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH" > /dev/null 2>&1
print_color "success" "Solana CLI installed."

# Section 4: Switch to Xolana Network
print_color "info" "\n===== 4/10: Switch to Xolana Network ====="

solana config set -u http://xolana.xen.network:8899 > /dev/null 2>&1
network_url=$(solana config get | grep 'RPC URL' | awk '{print $NF}')
if [ "$network_url" != "http://xolana.xen.network:8899" ]; then
    print_color "error" "Failed to switch to Xolana network."
    exit 1
fi
print_color "success" "Switched to Xolana network."

# Section 5: Wallets Creation
print_color "info" "\n===== 5/10: Creating Wallets ====="

# Ensure directory exists
mkdir -p "$install_dir"

# Identity wallet
if [ ! -f "$install_dir/identity.json" ]; then
    solana-keygen new --no-passphrase --outfile $install_dir/identity.json > /dev/null 2>&1
    identity_pubkey=$(solana-keygen pubkey $install_dir/identity.json)
    if [ -z "$identity_pubkey" ]; then
        echo "Error creating identity wallet"
        exit 1
    fi
    print_color "success" "Identity wallet created: $identity_pubkey"
else
    identity_pubkey=$(solana-keygen pubkey $install_dir/identity.json)
    print_color "info" "Identity wallet already exists: $identity_pubkey"
fi

# Vote wallet
if [ ! -f "$install_dir/vote.json" ]; then
    solana-keygen new --no-passphrase --outfile $install_dir/vote.json > /dev/null 2>&1
    vote_pubkey=$(solana-keygen pubkey $install_dir/vote.json)
    print_color "success" "Vote wallet created: $vote_pubkey"
else
    vote_pubkey=$(solana-keygen pubkey $install_dir/vote.json)
    print_color "info" "Vote wallet already exists: $vote_pubkey"
fi

# Stake wallet
if [ ! -f "$install_dir/stake.json" ]; then
    solana-keygen new --no-passphrase --outfile $install_dir/stake.json > /dev/null 2>&1
    stake_pubkey=$(solana-keygen pubkey $install_dir/stake.json)
    print_color "success" "Stake wallet created: $stake_pubkey"
else
    stake_pubkey=$(solana-keygen pubkey $install_dir/stake.json)
    print_color "info" "Stake wallet already exists: $stake_pubkey"
fi

# Withdrawer wallet
if [ ! -f "$HOME/.config/solana/withdrawer.json" ]; then
    solana-keygen new --no-passphrase --outfile $HOME/.config/solana/withdrawer.json > /dev/null 2>&1
    withdrawer_pubkey=$(solana-keygen pubkey $HOME/.config/solana/withdrawer.json)
    print_color "success" "Withdrawer wallet created: $withdrawer_pubkey"
else
    withdrawer_pubkey=$(solana-keygen pubkey $HOME/.config/solana/withdrawer.json)
    print_color "info" "Withdrawer wallet already exists: $withdrawer_pubkey"
fi

# Section 6: Request Faucet Funds - Add retry logic
print_color "info" "\n===== 6/10: Requesting Faucet Funds ====="
attempt=0
max_attempts=5
while [ "$attempt" -lt "$max_attempts" ]; do
    response=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"pubkey\":\"$identity_pubkey\"}" https://xolana.xen.network/faucet)
    if echo "$response" | grep -q "Please wait"; then
        wait_message=$(echo "$response" | sed -n 's/.*"message":"\([^"]*\)".*/\1/p')
        print_color "error" "Faucet request failed: $wait_message"
    elif echo "$response" | grep -q '"success":true'; then
        print_color "success" "5 SOL requested successfully."
    else
        print_color "error" "Faucet request failed. Response: $response"
    fi

    balance=$(solana balance $identity_pubkey)
    
    if [ "$balance" != "0 SOL" ]; then
        print_color "success" "Identity funded with $balance."
        break
    else
        print_color "error" "Failed to get 5 SOL. Retrying... ($((attempt + 1))/$max_attempts)"
        attempt=$((attempt + 1))
        sleep 10
    fi
done

if [ "$attempt" -eq "$max_attempts" ]; then
    print_color "error" "Failed to fund identity wallet after $max_attempts attempts. Exiting."
    exit 1
fi

# Section 7: Create Vote Account - Validate if account exists and has correct owner
print_color "info" "\n===== 7/10: Creating Vote Account ====="

vote_account_exists=$(solana vote-account $install_dir/vote.json > /dev/null 2>&1 && echo "true" || echo "false")
if [ "$vote_account_exists" == "true" ]; then
    print_color "info" "Vote account already exists: $vote_pubkey"
else
    solana create-vote-account $install_dir/vote.json $install_dir/identity.json $withdrawer_pubkey --commission 5 > /dev/null 2>&1
    print_color "success" "Vote account created."
fi

# Section 10: Start Validator Service with Dynamic RPC Ports
print_color "prompt" "\nPlease enter a unique RPC port (default is 8899):"
read rpc_port
if [ -z "$rpc_port" ]; then
    rpc_port=8899
fi

print_color "prompt" "Enter the entrypoint for the network (default is 216.202.227.220:8001):"
read entrypoint
if [ -z "$entrypoint" ]; then
    entrypoint="216.202.227.220:8001"
fi

print_color "success" "Starting Validator..."
solana-validator --identity $install_dir/identity.json \
    --vote-account $install_dir/vote.json \
    --rpc-port $rpc_port \
    --entrypoint $entrypoint \
    --full-rpc-api \
    --log - \
    --max-genesis-archive-unpacked-size 1073741824 \
    --no-incremental-snapshots \
    --require-tower \
    --enable-rpc-transaction-history \
    --enable-extended-tx-metadata-storage \
    --skip-startup-ledger-verification \
    --no-poh-speed-test \
    --bind-address 0.0.0.0
