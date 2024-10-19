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

# Prompt for verbose output
print_color "prompt" "Do you want to enable verbose output during installation? [y/n]"
read verbose
if [ "$verbose" == "y" ]; then
    exec 3>&1
else
    exec 3>/dev/null
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
dependencies=(curl wget jq)
for cmd in "${dependencies[@]}"; do
    install_package $cmd
done

# Section 2: Setup Validator Directory
print_color "info" "\n===== 2/10: Validator Directory Setup ====="

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

# Section 3: Install Rust
print_color "info" "\n===== 3/10: Rust Installation ====="

if ! command -v rustc &> /dev/null; then
    print_color "info" "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >&3 2>&1
    . "$HOME/.cargo/env" > /dev/null 2>&1
    if ! command -v rustc &> /dev/null; then
        print_color "error" "Rust installation failed."
        exit 1
    fi
    print_color "success" "Rust installed: $(rustc --version)"
else
    print_color "success" "Rust is already installed: $(rustc --version)"
fi

# Section 4: Install Solana CLI
print_color "info" "\n===== 4/10: Solana CLI Installation ====="

# Define the Solana CLI version
SOLANA_CLI_VERSION="v1.18.25"

print_color "info" "Installing Solana CLI version $SOLANA_CLI_VERSION..."
sh -c "$(curl -sSfL https://release.solana.com/$SOLANA_CLI_VERSION/install)" >&3 2>&1
if ! command -v solana &> /dev/null; then
    print_color "error" "Solana CLI installation failed."
    exit 1
fi

# Add Solana to PATH and reload profiles
profile_files=(~/.profile ~/.bashrc ~/.zshrc)
for profile in "${profile_files[@]}"; do
    if [ -f "$profile" ]; then
        if ! grep -q 'solana/install/active_release/bin' "$profile"; then
            echo 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' >> "$profile"
            print_color "info" "Added Solana to PATH in $profile"
        fi
    fi
done
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"
print_color "success" "Solana CLI installed: $(solana --version)"

# Section 5: Switch to Xolana Network
print_color "info" "\n===== 5/10: Switch to Xolana Network ====="

default_network_url="http://xolana.xen.network:8899"
print_color "prompt" "Enter the network RPC URL (default: $default_network_url):"
read network_url
if [ -z "$network_url" ]; then
    network_url=$default_network_url
fi

solana config set -u $network_url > /dev/null 2>&1
network_url_set=$(solana config get | grep 'RPC URL' | awk '{print $NF}')
if [ "$network_url_set" != "$network_url" ]; then
    print_color "error" "Failed to switch to network $network_url."
    exit 1
fi
print_color "success" "Switched to network: $network_url"

# Section 6: Wallets Creation
print_color "info" "\n===== 6/10: Creating Wallets ====="

# Function to create a wallet if it doesn't exist
function create_wallet {
    local wallet_path=$1
    local wallet_name=$2
    local pubkey
    if [ ! -f "$wallet_path" ]; then
        solana-keygen new $passphrase_option --outfile "$wallet_path" > /dev/null 2>&1
        pubkey=$(solana-keygen pubkey "$wallet_path")
        if [ -z "$pubkey" ]; then
            print_color "error" "Error creating $wallet_name wallet" >&2
            exit 1
        fi
        print_color "success" "$wallet_name wallet created: $pubkey" >&2
    else
        pubkey=$(solana-keygen pubkey "$wallet_path")
        print_color "info" "$wallet_name wallet already exists: $pubkey" >&2
    fi
    echo "$pubkey"
}

# Create wallets
identity_pubkey=$(create_wallet "$install_dir/identity.json" "Identity")
vote_pubkey=$(create_wallet "$install_dir/vote.json" "Vote")
stake_pubkey=$(create_wallet "$install_dir/stake.json" "Stake")
withdrawer_pubkey=$(create_wallet "$HOME/.config/solana/withdrawer.json" "Withdrawer")

# Secure key files
chmod 600 "$install_dir"/*.json
chmod 600 "$HOME/.config/solana/withdrawer.json"

# Set the default keypair to the identity keypair
solana config set --keypair "$install_dir/identity.json" > /dev/null 2>&1
print_color "info" "Default keypair set to identity keypair."

# Display generated keys and pause for user to save them
print_color "info" "\nPlease save the following keys:\n"
print_color "info" "Identity Public Key: $identity_pubkey"
print_color "info" "Vote Public Key: $vote_pubkey"
print_color "info" "Stake Public Key: $stake_pubkey"
print_color "info" "Withdrawer Public Key: $withdrawer_pubkey"
print_color "prompt" "\nPress Enter after saving the keys."
read -r

# Section 7: Requesting Faucet Funds with User Option
print_color "info" "\n===== 7/10: Requesting Faucet Funds ====="
attempt=0
max_attempts=5
cooldown_wait_time=480  # 8 minutes in seconds

while [ "$attempt" -lt "$max_attempts" ]; do
    response=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"pubkey\":\"$identity_pubkey\"}" https://xolana.xen.network/faucet)
    print_color "info" "Faucet response: $response" >&2

    # Check if response is valid JSON
    if echo "$response" | jq empty >/dev/null 2>&1; then
        success=$(echo "$response" | jq -r '.success')
        message=$(echo "$response" | jq -r '.message')
    else
        print_color "error" "Invalid JSON response from faucet: $response"
        success="false"
        message="Invalid JSON response"
    fi

    if [ "$success" == "true" ]; then
        print_color "success" "5 SOL requested successfully."
        balance=$(solana balance $identity_pubkey || echo "0 SOL")
        if [[ "$balance" != *"0 SOL"* ]]; then
            print_color "success" "Identity funded with $balance."
            break
        fi
    elif [[ "$message" == *"Please wait"* ]]; then
        attempt=$((attempt + 1))
        if [ "$attempt" -ge 3 ]; then
            print_color "prompt" "You've reached $attempt unsuccessful attempts."
            print_color "prompt" "Do you want to wait for the cooldown and retry automatically? [y/n]"
            read user_choice
            if [ "$user_choice" == "y" ]; then
                print_color "info" "Waiting for the cooldown period of $cooldown_wait_time seconds..."
                sleep $cooldown_wait_time
            else
                print_color "info" "You can manually request funds later using the following command:"
                echo "curl -X POST -H \"Content-Type: application/json\" -d '{\"pubkey\":\"$identity_pubkey\"}' https://xolana.xen.network/faucet"
                print_color "error" "Exiting the script as per user request."
                exit 1
            fi
        else
            print_color "error" "Faucet request failed: $message"
            print_color "info" "Retrying in 10 seconds... ($attempt/$max_attempts)"
            sleep 10
        fi
    else
        print_color "error" "Faucet request failed. Response: $response"
        attempt=$((attempt + 1))
        print_color "info" "Retrying in 10 seconds... ($attempt/$max_attempts)"
        sleep 10
    fi
done

if [ "$attempt" -eq "$max_attempts" ]; then
    print_color "error" "Failed to fund identity wallet after $max_attempts attempts. Exiting."
    exit 1
fi

# Section 8: Create Stake Account
print_color "info" "\n===== 8/10: Creating Stake Account ====="

stake_account_exists=$(solana stake-account $stake_pubkey > /dev/null 2>&1 && echo "true" || echo "false")
if [ "$stake_account_exists" == "true" ]; then
    stake_account_info=$(solana stake-account $stake_pubkey --output json)
    stake_account_owner=$(echo "$stake_account_info" | jq -r '.owner')
    if [ "$stake_account_owner" != "Stake11111111111111111111111111111111111111" ]; then
        print_color "error" "Stake account ownership mismatch. Expected Stake11111111111111111111111111111111111111 but got $stake_account_owner."
        exit 1
    else
        print_color "info" "Stake account already exists and is owned by the correct program."
    fi
else
    solana create-stake-account $install_dir/stake.json 5 --from $install_dir/identity.json >&3
    print_color "success" "Stake account created."

    # Delegate stake to the vote account
    solana delegate-stake $install_dir/stake.json $install_dir/vote.json >&3
    print_color "success" "Stake delegated to vote account: $vote_pubkey"
fi

# Section 9: Start Validator Service with Systemd
print_color "info" "\n===== 9/10: Starting Validator Service ====="

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

# Create a systemd service file
sudo tee /etc/systemd/system/solana-validator.service > /dev/null <<EOL
[Unit]
Description=Solana Validator Service
After=network-online.target

[Service]
User=$USER
WorkingDirectory=$install_dir
ExecStart=$(which solana-validator) \\
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
    $additional_options
Restart=always
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOL

# Reload systemd and start the service
sudo systemctl daemon-reload
sudo systemctl enable solana-validator
sudo systemctl start solana-validator
print_color "success" "Validator service started and enabled."

# Section 10: Summary and Next Steps
print_color "success" "\n===== Installation and Setup Complete! ====="
print_color "info" "Validator is running as a systemd service named 'solana-validator'."
print_color "info" "You can check the status with: sudo systemctl status solana-validator"
print_color "info" "Logs are being written to: $install_dir/validator.log"
print_color "info" "To stop the validator: sudo systemctl stop solana-validator"
print_color "info" "To view logs: tail -f $install_dir/validator.log"
