#!/bin/bash
set -e

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

# Ensure the script is run on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    print_color "error" "This script is designed for Linux systems."
    exit 1
fi

# Prompt for setting passphrase on wallets
print_color "prompt" "Do you want to secure your wallets with a passphrase? [y/n]"
read set_passphrase
if [ "$set_passphrase" == "y" ]; then
    passphrase_option=""
    print_color "info" "You will be prompted to enter a passphrase for each wallet."
else
    passphrase_option="--no-passphrase"
fi

# Section 1: Install Dependencies
print_color "info" "\n===== 1/10: Installing Dependencies ====="

# Function to install packages
function install_package {
    local package=$1
    if command -v $package &> /dev/null; then
        print_color "success" "$package is already installed."
    else
        print_color "info" "Installing $package..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update >&3 2>&1
            sudo apt-get install -y $package >&3 2>&1
        elif command -v yum &> /dev/null; then
            sudo yum install -y $package >&3 2>&1
        elif command -v dnf &> /dev/null; then
            sudo dnf install -y $package >&3 2>&1
        elif command -v pacman &> /dev/null; then
            sudo pacman -Sy $package >&3 2>&1
        else
            print_color "error" "Unsupported package manager. Please install $package manually."
            exit 1
        fi
        print_color "success" "$package installed."
    fi
}

# Install required dependencies
dependencies=(curl wget jq bc screen)
for cmd in "${dependencies[@]}"; do
    install_package $cmd
done

# The rest of the script remains the same until Section 10

# ... (Sections 2 to 9)

# Section 10: Start Validator Without Systemd
print_color "info" "\n===== 10/10: Starting Validator ====="

# Prompt for unique RPC port
print_color "prompt" "\nPlease enter a unique RPC port (default is 8899):"
read rpc_port
if [ -z "$rpc_port" ]; then
    rpc_port=8899
fi

# Prompt for entrypoint
default_entrypoint="216.202.227.220:8001"
print_color "prompt" "Enter the entrypoint for the network (default: $default_entrypoint):"
read entrypoint
if [ -z "$entrypoint" ]; then
    entrypoint=$default_entrypoint
fi

# Prompt for additional validator options
print_color "prompt" "Enter any additional solana-validator options (or press Enter to skip):"
read additional_options

# Create ledger directory
ledger_dir="$install_dir/ledger"
mkdir -p "$ledger_dir"

# Build the solana-validator command
validator_cmd="$(which solana-validator) \\
    --identity $install_dir/identity.json \\
    --vote-account $install_dir/vote.json \\
    --ledger $ledger_dir \\
    --rpc-port $rpc_port \\
    --entrypoint $entrypoint \\
    --full-rpc-api \\
    --log $install_dir/validator.log \\
    --max-genesis-archive-unpacked-size 1073741824 \\
    --require-tower \\
    --enable-rpc-transaction-history \\
    --enable-extended-tx-metadata-storage \\
    --bind-address 0.0.0.0 \\
    $additional_options"

# Run the validator in a detached screen session
print_color "info" "Starting the validator in a detached screen session named 'solana-validator'..."
screen -dmS solana-validator bash -c "$validator_cmd"

print_color "success" "Validator started in a detached screen session."
print_color "info" "You can attach to the session using: screen -r solana-validator"
print_color "info" "To detach from the session, press: Ctrl+A then D"
print_color "info" "Logs are being written to: $install_dir/validator.log"
