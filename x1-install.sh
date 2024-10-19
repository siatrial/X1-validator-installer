#!/bin/bash

# x1-install.sh
# A script to set up a Solana validator on the Xolana network

# Color functions for output
print_color() {
    case $1 in
        "info") color="96m";;       # Light Cyan
        "success") color="92m";;    # Light Green
        "error") color="91m";;      # Light Red
        "warning") color="93m";;    # Light Yellow
        "prompt") color="95m";;     # Light Magenta
        *) color="0m";;             # Default color
    esac
    echo -e "\e[${color}$2\e[0m"
}

# Section 0: Introduction and Passphrase
echo "Do you want to secure your wallets with a passphrase? [y/n]"
read -p "" passphrase_choice

if [[ "$passphrase_choice" == "y" || "$passphrase_choice" == "Y" ]]; then
    read -s -p "Enter passphrase: " wallet_passphrase
    echo
    read -s -p "Confirm passphrase: " wallet_passphrase_confirm
    echo
    if [ "$wallet_passphrase" != "$wallet_passphrase_confirm" ]; then
        print_color "error" "Passphrases do not match. Exiting."
        exit 1
    fi
    wallet_passphrase_option="--passphrase"
else
    wallet_passphrase=""
    wallet_passphrase_option=""
fi

# Section 1: Install Dependencies
print_color "info" "\n===== 1/11: Installing Dependencies ====="

# Check and install dependencies
dependencies=(curl wget jq bc screen)
for dep in "${dependencies[@]}"; do
    if ! command -v $dep &> /dev/null; then
        print_color "info" "Installing $dep..."
        sudo apt-get update && sudo apt-get install -y $dep
        print_color "success" "$dep installed."
    else
        print_color "info" "$dep is already installed."
    fi
done

# Section 2: Validator Directory Setup
print_color "info" "\n===== 2/11: Validator Directory Setup ====="
read -p "Validator Directory (press Enter for default: /root/x1_validator): " validator_dir
validator_dir=${validator_dir:-/root/x1_validator}

if [ -d "$validator_dir" ]; then
    echo "Directory exists. Delete it? [y/n]"
    read -p "" delete_choice
    if [[ "$delete_choice" == "y" || "$delete_choice" == "Y" ]]; then
        rm -rf "$validator_dir"
        print_color "success" "Deleted $validator_dir"
    else
        print_color "error" "Directory already exists. Exiting."
        exit 1
    fi
fi

mkdir -p "$validator_dir"
print_color "success" "Directory created: $validator_dir"

# Section 3: Rust Installation
print_color "info" "\n===== 3/11: Rust Installation ====="
curl https://sh.rustup.rs -sSf | sh -s -- -y
source $HOME/.cargo/env
print_color "success" "Rust installed: $(rustc --version)"

# Section 4: Solana CLI Installation
print_color "info" "\n===== 4/11: Solana CLI Installation ====="
export PATH="/root/.local/share/solana/install/active_release/bin:$PATH"
sh -c "$(curl -sSfL https://release.solana.com/v1.18.25/install)"
print_color "success" "Solana CLI installed: $(solana --version)"

# Section 5: Switch to Xolana Network
print_color "info" "\n===== 5/11: Switch to Xolana Network ====="
read -p "Enter the network RPC URL (default: http://xolana.xen.network:8899): " network_url
network_url=${network_url:-http://xolana.xen.network:8899}

solana config set --url "$network_url"
print_color "success" "Switched to network: $network_url"

# Section 6: Creating Wallets
print_color "info" "\n===== 6/11: Creating Wallets ====="

# Create wallets with or without passphrase
identity_keypair_path="$validator_dir/identity.json"
vote_keypair_path="$validator_dir/vote-account-keypair.json"
stake_keypair_path="$validator_dir/stake-account-keypair.json"
withdrawer_keypair_path="$validator_dir/withdrawer-keypair.json"

solana-keygen new --outfile "$identity_keypair_path" $wallet_passphrase_option $wallet_passphrase --no-bip39-passphrase
solana-keygen new --outfile "$vote_keypair_path" --no-bip39-passphrase
solana-keygen new --outfile "$stake_keypair_path" --no-bip39-passphrase
if [ ! -f "$withdrawer_keypair_path" ]; then
    solana-keygen new --outfile "$withdrawer_keypair_path" --no-bip39-passphrase
else
    print_color "warning" "Withdrawer wallet already exists: $(solana-keygen pubkey $withdrawer_keypair_path)"
fi

identity_pubkey=$(solana-keygen pubkey "$identity_keypair_path")
vote_pubkey=$(solana-keygen pubkey "$vote_keypair_path")
stake_pubkey=$(solana-keygen pubkey "$stake_keypair_path")
withdrawer_pubkey=$(solana-keygen pubkey "$withdrawer_keypair_path")

solana config set --keypair "$identity_keypair_path"

print_color "info" "\nPlease save the following keys:\n"
print_color "info" "Identity Public Key: $identity_pubkey"
print_color "info" "Vote Public Key: $vote_pubkey"
print_color "info" "Stake Public Key: $stake_pubkey"
print_color "info" "Withdrawer Public Key: $withdrawer_pubkey"
print_color "prompt" "\nPress Enter after saving the keys."
read -p ""

# Section 7: Requesting Faucet Funds
print_color "info" "\n===== 7/11: Requesting Faucet Funds ====="

# Attempt to request funds from the faucet
faucet_response=$(curl -s -X POST -H "Content-Type: application/json" -d '{"pubkey":"'"$identity_pubkey"'"}' https://xolana.xen.network/faucet)
faucet_success=$(echo "$faucet_response" | jq -r '.success')
faucet_message=$(echo "$faucet_response" | jq -r '.message')

if [ "$faucet_success" == "true" ]; then
    print_color "success" "Faucet funds requested successfully."
else
    print_color "error" "Faucet request failed: $faucet_message."
    print_color "info" "You can manually fund your Identity Wallet to proceed."
    print_color "info" "Identity Wallet Address: $identity_pubkey"
    print_color "prompt" "Press Enter once you have funded the wallet to continue."
    read -p ""
fi

# Verify that the Identity Wallet has sufficient balance
identity_balance=$(solana balance $identity_pubkey | awk '{print $1}')
min_balance_required=1  # Adjust as needed

while (( $(echo "$identity_balance < $min_balance_required" | bc -l) )); do
    print_color "error" "Identity wallet balance is insufficient ($identity_balance SOL)."
    print_color "prompt" "Please fund the Identity Wallet with at least $min_balance_required SOL."
    print_color "prompt" "Press Enter after funding the wallet to check the balance again."
    read -p ""
    identity_balance=$(solana balance $identity_pubkey | awk '{print $1}')
done

print_color "success" "Identity wallet has sufficient balance: $identity_balance SOL."

# Section 8: Create Vote Account
print_color "info" "\n===== 8/11: Creating Vote Account ====="
solana vote-account create "$vote_keypair_path" "$withdrawer_pubkey" --commission 10
print_color "success" "Vote account created with commission set to 10%."

# Section 9: Create Stake Account and Delegate
print_color "info" "\n===== 9/11: Creating Stake Account and Delegating ====="
solana stake-account create "$stake_keypair_path" --withdrawer "$withdrawer_pubkey" --stake 1
solana stake-account delegate "$stake_pubkey" "$vote_pubkey"
print_color "success" "Stake account created and delegated."

# Section 10: Create Systemd Service
print_color "info" "\n===== 10/11: Setting Up Systemd Service ====="

sudo tee /etc/systemd/system/solana-validator.service > /dev/null <<EOF
[Unit]
Description=Solana Validator
After=network.target

[Service]
User=$(whoami)
ExecStart=$(which solana-validator) \\
    --identity "$identity_keypair_path" \\
    --vote-account "$vote_keypair_path" \\
    --rpc-bind-address 0.0.0.0 \\
    --dynamic-port-range 8000-8020 \\
    --entrypoint entrypoint.mainnet-beta.solana.com:8001 \\
    --expected-genesis-hash "$(solana genesis-hash)" \\
    --wal-recovery-mode skip_any_corrupted_record \\
    --limit-ledger-size \\
    --log /var/log/solana/solana-validator.log
Restart=always
RestartSec=3
LimitNOFILE=500000

[Install]
WantedBy=multi-user.target
EOF

print_color "success" "Systemd service file created at /etc/systemd/system/solana-validator.service"

# Section 11: Start the Validator
print_color "info" "\n===== 11/11: Starting the Validator ====="
sudo systemctl daemon-reload
sudo systemctl enable solana-validator
sudo systemctl start solana-validator
print_color "success" "Solana validator service started."

print_color "info" "\n===== Setup Complete ====="
print_color "info" "You can check the status of your validator with:"
print_color "info" "  sudo systemctl status solana-validator"
print_color "info" "You can view logs with:"
print_color "info" "  sudo journalctl -u solana-validator -f"

