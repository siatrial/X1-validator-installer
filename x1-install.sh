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

# Function to install missing dependencies
install_dependencies() {
    local packages=("$@")
    echo "Attempting to install missing dependencies: ${packages[*]}"

    if [[ -f /etc/debian_version ]]; then
        sudo apt update
        sudo apt install -y "${packages[@]}"
    elif [[ -f /etc/redhat-release ]]; then
        sudo yum install -y epel-release
        sudo yum install -y "${packages[@]}"
    elif [[ -f /etc/fedora-release ]]; then
        sudo dnf install -y "${packages[@]}"
    elif [[ -f /etc/arch-release ]]; then
        sudo pacman -Syu --noconfirm "${packages[@]}"
    elif [[ -f /etc/openSUSE-release ]]; then
        sudo zypper install -y "${packages[@]}"
    else
        print_color "error" "Unsupported Linux distribution. Please install the following dependencies manually: ${packages[*]}"
        exit 1
    fi
}

# Ensure the script is run on Linux
if [[ "$OSTYPE" != "linux-gnu"* ]]; then
    print_color "error" "This script is designed for Linux systems."
    exit 1
fi

# Check for required commands and install if missing
dependencies=(curl wget jq)
missing_dependencies=()
for cmd in "${dependencies[@]}"; do
    if ! command -v $cmd &> /dev/null; then
        missing_dependencies+=("$cmd")
    fi
done

if [ ${#missing_dependencies[@]} -ne 0 ]; then
    print_color "info" "The following dependencies are missing: ${missing_dependencies[*]}"
    print_color "prompt" "Do you want to install them now? [y/n]"
    read install_choice
    if [[ "$install_choice" =~ ^[Yy]$ ]]; then
        install_dependencies "${missing_dependencies[@]}"
        # Verify installation
        for cmd in "${missing_dependencies[@]}"; do
            if ! command -v $cmd &> /dev/null; then
                print_color "error" "Failed to install '$cmd'. Please install it manually and rerun the script."
                exit 1
            else
                print_color "success" "Installed '$cmd' successfully."
            fi
        done
    else
        print_color "error" "Cannot proceed without installing the required dependencies."
        exit 1
    fi
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
    print_color "prompt" "Directory '$install_dir' already exists. Do you want to use it? [y/n]"
    read use_existing_dir
    if [[ "$use_existing_dir" =~ ^[Yy]$ ]]; then
        print_color "info" "Using existing directory: $install_dir"
    else
        print_color "prompt" "Do you want to delete the existing directory? [y/n]"
        read delete_choice
        if [[ "$delete_choice" =~ ^[Yy]$ ]]; then
            rm -rf "$install_dir" > /dev/null 2>&1
            print_color "info" "Deleted $install_dir"
            mkdir -p "$install_dir" > /dev/null 2>&1
            print_color "success" "Directory created: $install_dir"
        else
            print_color "error" "Please choose a different directory or delete the existing one."
            exit 1
        fi
    fi
else
    mkdir -p "$install_dir" > /dev/null 2>&1
    print_color "success" "Directory created: $install_dir"
fi

cd "$install_dir" || exit 1

# Section 2: Install Rust
print_color "info" "\n===== 2/10: Rust Installation ====="

if ! command -v rustc &> /dev/null; then
    print_color "info" "Installing Rust..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y >&3 2>&1
    source "$HOME/.cargo/env" > /dev/null 2>&1
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
sh -c "$(curl -sSfL https://release.solana.com/$SOLANA_CLI_VERSION/install)"  # Remove the >&3 redirection

# Update PATH immediately after installation
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"

# Verify Solana CLI installation
if ! command -v solana &> /dev/null; then
    print_color "error" "Solana CLI installation failed."
    print_color "info" "Please manually add Solana to your PATH:"
    print_color "info" 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"'
    exit 1
fi

# Add Solana to PATH in profile files for future sessions
profile_files=(~/.profile ~/.bashrc ~/.zshrc)
for profile in "${profile_files[@]}"; do
    if [ -f "$profile" ];then
        if ! grep -q 'solana/install/active_release/bin' "$profile"; then
            echo 'export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"' >> "$profile"
            print_color "info" "Added Solana to PATH in $profile"
        fi
    fi
done

print_color "success" "Solana CLI installed: $(solana --version)"

# Section 4: Switch to Xolana Network
print_color "info" "\n===== 4/10: Switch to Xolana Network ====="

default_network_url="http://xolana.xen.network:8899"
print_color "prompt" "Enter the network RPC URL (press Enter for default: $default_network_url):"
read network_url
if [ -z "$network_url" ];then
    network_url=$default_network_url
fi

solana config set -u "$network_url" > /dev/null 2>&1
network_url_set=$(solana config get | grep 'RPC URL' | awk '{print $NF}')
if [ "$network_url_set" != "$network_url" ];then
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

    if [ -f "$wallet_path" ];then
        print_color "prompt" "$wallet_name wallet already exists at '$wallet_path'. Do you want to reuse it? [y/n]"
        read reuse_choice
        if [[ "$reuse_choice" =~ ^[Yy]$ ]]; then
            pubkey=$(solana-keygen pubkey "$wallet_path")
            if [ -z "$pubkey" ];then
                print_color "error" "Failed to retrieve public key from existing $wallet_name wallet."
                exit 1
            fi
            print_color "info" "Reusing existing $wallet_name wallet: $pubkey"
            echo "$pubkey"
        else
            # Create a new wallet
            solana-keygen new --no-passphrase --outfile "$wallet_path" > /dev/null 2>&1
            pubkey=$(solana-keygen pubkey "$wallet_path")
            if [ -z "$pubkey" ];then
                print_color "error" "Error creating new $wallet_name wallet."
                exit 1
            fi
            print_color "success" "New $wallet_name wallet created: $pubkey"
            echo "$pubkey"
        fi
    else
        # Create a new wallet
        solana-keygen new --no-passphrase --outfile "$wallet_path" > /dev/null 2>&1
        pubkey=$(solana-keygen pubkey "$wallet_path")
        if [ -z "$pubkey" ];then
            print_color "error" "Error creating $wallet_name wallet."
            exit 1
        fi
        print_color "success" "$wallet_name wallet created: $pubkey"
        echo "$pubkey"
    fi
}

identity_pubkey=$(handle_wallet "$install_dir/identity.json" "Identity")
vote_pubkey=$(handle_wallet "$install_dir/vote.json" "Vote")
stake_pubkey=$(handle_wallet "$install_dir/stake.json" "Stake")
withdrawer_pubkey=$(handle_wallet "$HOME/.config/solana/withdrawer.json" "Withdrawer")

# Display generated keys and pause for user to save them
print_color "info" "\nPlease save the following keys securely:\n"
print_color "info" "Identity Public Key: $identity_pubkey"
print_color "info" "Vote Public Key: $vote_pubkey"
print_color "info" "Stake Public Key: $stake_pubkey"
print_color "info" "Withdrawer Public Key: $withdrawer_pubkey"
print_color "prompt" "\nPress Enter after saving the keys."
read -r

# Section 6: Request Faucet Funds
print_color "info" "\n===== 6/10: Requesting Faucet Funds ====="

request_faucet() {
    # New faucet URL
    faucet_url="https://xolana.xen.network/web_faucet"

    # Make the POST request to the faucet
    response=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"pubkey\":\"$1\"}" "$faucet_url")

    # Check if response is valid JSON
    if echo "$response" | jq empty > /dev/null 2>&1; then
        # Process the response as JSON
        if echo "$response" | grep -q '"success":true'; then
            print_color "success" "5 SOL requested successfully."
        else
            # Extract the message field to show specific error
            error_message=$(echo "$response" | jq -r '.message // "Unknown error"')
            print_color "error" "Faucet request failed. Error: $error_message"
        fi
    else
        # Handle case where the response is not valid JSON
        print_color "error" "Unexpected response from faucet: $response"
    fi
}




# Request funds from the faucet for the identity public key
request_faucet $identity_pubkey

print_color "info" "Waiting 30 seconds to verify balance..."
sleep 30

# Check if the balance has been updated
balance=$(solana balance $identity_pubkey 2>&1)
if [[ "$balance" != "0 SOL" ]]; then
    print_color "success" "Identity wallet funded with $balance."
else
    print_color "error" "Failed to receive 5 SOL. Exiting."
    exit 1
fi

# Section 7: Start Validator

print_color "info" "\n===== 7/10: Starting the Validator ====="

print_color "info" "Starting the validator using identity, vote, and stake accounts..."

nohup solana-validator --identity "$install_dir/identity.json" \
    --vote-account "$install_dir/vote.json" \
    --rpc-port 8899 \
    --entrypoint xolana.xen.network:8001 \
    --full-rpc-api \
    --log "$install_dir/validator.log" \
    --max-genesis-archive-unpacked-size 1073741824 \
    --no-incremental-snapshots \
    --require-tower \
    --enable-rpc-transaction-history \
    --enable-extended-tx-metadata-storage \
    --skip-startup-ledger-verification \
    --rpc-pubsub-enable-block-subscription &

print_color "success" "Validator started in the background. Logs are being written to $install_dir/validator.log"

# Tuning the system based on guide recommendations (optional)
print_color "info" "Tuning system for performance..."

sudo bash -c "cat >/etc/sysctl.d/21-solana-validator.conf <<EOF
# Increase UDP buffer sizes
net.core.rmem_default = 134217728
net.core.rmem_max = 134217728
net.core.wmem_default = 134217728
net.core.wmem_max = 134217728

# Increase memory mapped files limit
vm.max_map_count = 1000000

# Increase number of allowed open file descriptors
fs.nr_open = 1000000
EOF"

sudo sysctl -p /etc/sysctl.d/21-solana-validator.conf

sudo bash -c "cat >/etc/security/limits.d/90-solana-nofiles.conf <<EOF
# Increase process file descriptor count limit
* - nofile 1000000
EOF"

sudo systemctl daemon-reload
print_color "success" "System tuned successfully!"
