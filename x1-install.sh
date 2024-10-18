# Section 5: Wallets Creation - Add checks to prevent duplicate creation
print_color "info" "\n===== 5/10: Creating Wallets ====="

# Identity wallet
if [ ! -f "$install_dir/identity.json" ]; then
    solana-keygen new --no-passphrase --outfile $install_dir/identity.json > /dev/null 2>&1
    identity_pubkey=$(solana-keygen pubkey $install_dir/identity.json)
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
    request_faucet $identity_pubkey
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
