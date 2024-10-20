# X1 Validator Installer

This script automates the installation and setup of an Xolana X1 validator node, including creation of Solana accounts and key generation, airdrops, system tuning, etc.

## ⚙️ Prerequisites

Ensure you have the following installed on your system:
- Ubuntu Linux Server
- Ensure your dedicated server has at least: 128 GB RAM & 2 TB SSD.
  - For example, Xen.pub Validator is running on the following specs:
    - **CPU**: AMD Ryzen 9 7900X 12-Core Processor
    - **Memory (RAM)**: DDR5 4800MHz 128GB (4 x 32GB 4800MHz)
    - **Hard Disk**: Samsung SSD 980 PRO 2TB
    - **OS**: Ubuntu 22.04.4 LTS
    - **Bandwidth**: 1GBPS (10GB Port)
- Ensure your firewall allows TCP/UDP port range 8000-10000 (otherwise X1 won't be able to communicate)

## 🛠️ One-Liner Installation Command

To install the X1 Validator on your machine, use the following one-liner command. This command will download the `x1-install.sh` script from the repository, make it executable, and run it:

```bash
cd ~ && \
wget -O ~/x1-install.sh https://raw.githubusercontent.com/siatrial/X1-validator-installer/master/x1-install.sh && \
chmod +x ~/x1-install.sh && \
~/x1-install.sh

```

When the installation is completed, you can start your validator using the following command:

```bash
export PATH="$HOME/.local/share/solana/install/active_release/bin:$PATH"; ulimit -n 1000000; solana-validator --identity $HOME/x1_validator/identity.json --vote-account $HOME/x1_validator/vote.json --rpc-port 8899 --entrypoint 216.202.227.220:8001 --full-rpc-api --log - --max-genesis-archive-unpacked-size 1073741824 --no-incremental-snapshots --require-tower --enable-rpc-transaction-history --enable-extended-tx-metadata-storage --skip-startup-ledger-verification --no-poh-speed-test --expected-bank-slot-time-ms 400 --bind-address 0.0.0.0
```
Note: 
- Export PATH and ULIMIT should not be necessary, as script is also setting it during execution, but I included it just in case.
- **Important**: During installation, you’ll see a screen asking you to download and back up your keys from the displayed locations. Make sure to do this after installation. 


## 🚀 Running the Validator
As part of the setup, the script attempts to **airdrop 5 SOL (XN)** into the **identity wallet** using the **Xolana network faucet** at: https://xolana.xen.network/faucet.
This is because the SOL (XN) in the identity wallet is required to: 
- **Cover transaction fees** (e.g., votes, on-chain operations)
- **Initialize accounts** like the vote and stake accounts

### Staking Requirements

You can **start the validator** without staking any SOL (XN), as staking is **not required** to run it.
However, without staking, the validator will act as a **non-participating node** — it will sync with the network but **won't vote, participate in consensus, or earn rewards**.

To fully activate the validator and start earning rewards, you must:
1. **Stake SOL (XN) in a stake account** linked to the vote account.
2. Ensure your stake account meets the network’s **minimum staking requirements**.

Learn more about staking: [X1 Staking Documentation](https://docs.x1.xyz/validating/staking)



### SOL (XN) - Distribution Recommendations

- **Identity Wallet**: Keep at least **1-5 SOL (XN)** to cover fees for essential operations.
- **Stake Account**: Transfer **at least 1 SOL (XN)** into the stake account to begin earning rewards.



## 🎥 One-Liner Video Demo
One-Liner Video Demo: https://x.com/xenpub/status/1846402568030757357

## 📜 Licensing (MIT)
This project is licensed under the **MIT License**.

**MIT License Summary:**
- You can do almost anything with this code, as long as you provide proper attribution.
- The software is provided "as is," without warranty of any kind, express or implied.

## 🤝 Contributing & Feedback
This is the **first iteration** of the script, and while it aims to be a one-line way to install X1 Validator without any user input, **it may contain bugs or edge cases that have not been considered yet**. 
We encourage developers to **review the code** thoroughly and report or correct any mistakes they find.

If you have any suggestions for improvement or new features, please feel free to:
1. **Submit an issue** with detailed descriptions of the problem.
2. **Create a pull request** with your improvements to make the script more stable for everyone.
3. Help expand the functionality by **adding commits** that enhance performance, stability, or flexibility.

Together, we can **refine this project and make it more robust** over time!

Thank you for your contributions, reviews, and suggestions. Every bit of feedback helps the community!

## 📚 Other Resources
- See your validator online: http://x1val.online/
- Read Xen-Tzu's X1 Validator guide to understand how all this work: https://docs.x1.xyz/explorer
- X1 vs SOLANA: https://x.com/xenpub/status/1843837470821281953
- If you'd like to help, donate here: https://xen.pub/donate.php
