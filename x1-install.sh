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

# Check for required commands
dependencies=(curl wget jq)
for cmd in "${dependencies[@]}"; do
    if ! command -v $cmd &> /dev/null; then
        print_color "error" "Command '$cmd' not found. Please install it before running the script."
        exit 1
    fi
done

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

# Section 3: Install Solana CLI
print_color "info" "\n===== 3/10: Solana CLI Installation ====="

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

# Section 4: Switch to Xolana Network
print_color "info" "\n===== 4/10: Switch to Xolana Network ====="

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

# Section 5: Wallets Creation
print_color "info" "\n===== 5/10: Creating or Reusing Wallets ====="

# Function to create a wallet if it doesn't exist or if the user chooses to create a new one
function handle_wallet {
    local wallet_path=$1
    local wallet_name=$2

    if [ -f "$wallet_path" ]; then
        print_color "prompt" "$wallet_name wallet already exists at $wallet_path. Do you want to reuse it? [y/n]"
        read reuse_choice
        if [ "$reuse_choice" == "y" ]; then
            local pubkey
            pubkey=$(solana-keygen pubkey "$wallet_path")
            if [ -z "$pubkey" ]; then
                print_color "error" "Failed to retrieve public key from existing $wallet_name wallet."
                exit 1
            fi
            print_color "info" "Reusing existing $wallet_name wallet: $pubkey"
            echo "$pubkey"
        else
            # Create a new wallet
            solana-keygen new $passphrase_option --outfile "$wallet_path" > /dev/null 2>&1
            local new_pubkey
            new_pubkey=$(solana-keygen pubkey "$wallet_path")
            if [ -z "$new_pubkey" ]; then
                print_color "error" "Error creating new $wallet_name wallet."
                exit 1
            fi
            print_color "success" "New $wallet_name wallet created: $new_pubkey"
            echo "$new_pubkey"
        fi
    else
        # Create a new wallet
        solana-keygen new $passphrase_option --outfile "$wallet_path" > /dev/null 2>&1
        local new_pubkey
        new_pubkey=$(solana-keygen pubkey "$wallet_path")
        if [ -z "$new_pubkey" ]; then
            print_color "error" "Error creating $wallet_name wallet."
            exit 1
        fi
        print_color "success" "$wallet_name wallet created: $new_pubkey"
        echo "$new_pubkey"
    fi
}

# Create or reuse wallets
identity_pubkey=$(handle_wallet "$install_dir/identity.json" "Identity")
vote_pubkey=$(handle_wallet "$install_dir/vote.json" "Vote")
stake_pubkey=$(handle_wallet "$install_dir/stake.json" "Stake")
withdrawer_pubkey=$(handle_wallet "$HOME/.config/solana/withdrawer.json" "Withdrawer")

# Display generated keys and pause for user to save them
print_color "info" "\nPlease save the following keys:\n"
print_color "info" "Identity Public Key: $identity_pubkey"
print_color "info" "Vote Public Key: $vote_pubkey"
print_color "info" "Stake Public Key: $stake_pubkey"
print_color "info" "Withdrawer Public Key: $withdrawer_pubkey"
print_color "prompt" "\nPress Enter after saving the keys."
read -r

# Section 6: Manual Funding Instruction
print_color "info" "\n===== 6/10: Funding Identity Wallet ====="

print_color "info" "Instead of automatically requesting funds from the faucet, please manually fund your Identity wallet with 5 SOL."
print_color "info" "Use the following public key to receive funds:"
print_color "info" "$identity_pubkey"
print_color "info" "\nYou can use any Solana-compatible wallet or exchange to send 5 SOL to this address."

print_color "prompt" "Press Enter once you have funded the Identity wallet."
read -r

# Optionally, verify the balance
print_color "info" "Checking the balance of the Identity wallet..."
balance=$(solana balance $identity_pubkey)
if [[ "$balance" != *"0 SOL"* ]]; then
    print_color "success" "Identity wallet funded with $balance."
else
    print_color "error" "Identity wallet still has 0 SOL. Please ensure you have sent 5 SOL to $identity_pubkey."
    exit 1
fi

# Section 7: Create Vote Account - Validate if account exists and has correct owner
print_color "info" "\n===== 7/10: Creating Vote Account ====="

vote_account_exists=$(solana vote-account $vote_pubkey > /dev/null 2>&1 && echo "true" || echo "false")
if [ "$vote_account_exists" == "true" ]; then
    vote_account_info=$(solana vote-account $vote_pubkey --output json)
    vote_account_owner=$(echo "$vote_account_info" | jq -r '.nodePubkey')
    if [ "$vote_account_owner" != "$identity_pubkey" ]; then
        print_color "error" "Vote account owner mismatch. Expected $identity_pubkey but got $vote_account_owner."
        exit 1
    else
        print_color "info" "Vote account already exists and is owned by the correct identity."
    fi
else
    solana create-vote-account $install_dir/vote.json $install_dir/identity.json $withdrawer_pubkey --commission 5 >&3 2>&1
    print_color "success" "Vote account created."
fi

# Section 8: Start Validator Service with Systemd
print_color "info" "\n===== 8/10: Starting Validator Service ====="

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

# Create a systemd service file
sudo tee /etc/systemd/system/solana-validator.service > /dev/null <<EOL
[Unit]
Description=Solana Validator
After=network-online.target

[Service]
User=$USER
ExecStart=$(which solana-validator) --identity $install_dir/identity.json \\
    --vote-account $install_dir/vote.json \\
    --rpc-port $rpc_port \\
    --entrypoint $entrypoint \\
    --full-rpc-api \\
    --log $install_dir/validator.log \\
    --max-genesis-archive-unpacked-size 1073741824 \\
    --no-incremental-snapshots \\
    --require-tower \\
    --enable-rpc-transaction-history \\
    --enable-extended-tx-metadata-storage \\
    --skip-startup-ledger-verification \\
    --no-poh-speed-test \\
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

# Section 9: Summary and Next Steps
print_color "success" "\n===== Installation and Setup Complete! ====="
print_color "info" "Validator is running as a systemd service named 'solana-validator'."
print_color "info" "You can check the status with: sudo systemctl status solana-validator"
print_color "info" "Logs are being written to: $install_dir/validator.log"
print_color "info" "To stop the validator: sudo systemctl stop solana-validator"
print_color "info" "To view logs: tail -f $install_dir/validator.log"
