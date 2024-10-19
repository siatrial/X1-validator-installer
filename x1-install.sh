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
sh -c "$(curl -sSfL https://release.solana.com/$SOLANA_CLI_VERSION/install)" >&3 2>&1

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

# Section 6: Manual Funding Instruction
print_color "info" "\n===== 6/10: Funding Identity Wallet ====="

print_color "info" "Use the following public key to receive funds:"
print_color "info" "$identity_pubkey"

print_color "prompt" "Press Enter once you have funded the Identity wallet with at least 5 SOL."
read -r  # Wait for user input

# Check balance and provide better error handling
while true; do
    balance=$(solana balance "$identity_pubkey" 2>&1)

    # Check if the command returned an error
    if [[ "$balance" == *"error"* || "$balance" == *"command not found"* ]]; then
        print_color "error" "Failed to check wallet balance: $balance"
        exit 1
    elif [[ "$balance" == "0 SOL" ]]; then
        print_color "error" "Identity wallet still has 0 SOL. Please ensure you have sent 5 SOL to $identity_pubkey."
        print_color "prompt" "Press Enter to check again once you've funded the wallet."
        read -r  # Wait for user to confirm they've funded the wallet
    else
        print_color "success" "Identity wallet funded with $balance."
        break
    fi
done

# Continue with the next steps after successful funding
