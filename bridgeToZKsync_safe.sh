#!/usr/bin/env bash
set -euo pipefail

# ---------------------------
# Config (modify if needed)
# ---------------------------
REQUIRED_CMDS=(curl jq forge cast awk grep)
FOUNDARY_ZKSYNC_INSTALL_URL="https://raw.githubusercontent.com/matter-labs/foundry-zksync/master/foundryup/install"

# constants used in your original script
AMOUNT=${AMOUNT:-100000}

# default addresses (leave as-is unless you want to override in .env)
DEFAULTS=(
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
)

# helper: print error and exit
err() { echo "❌ $*" >&2; exit 1; }

info() { echo "ℹ️ $*"; }

# ---------------------------
# 1. Check basic commands
# ---------------------------
for cmd in "${REQUIRED_CMDS[@]}"; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Required command '$cmd' not found. Install it and re-run the script."
  fi
done

# ---------------------------
# 2. Ensure we're using ZKsync Foundry
# ---------------------------
# This script expects the matter-labs zksync foundry. The presence of 'foundryup-zksync'
# is a simple heuristic. If missing, offer to install it non-interactively.
if ! command -v foundryup-zksync >/dev/null 2>&1; then
  info "foundryup-zksync not found. Installing ZKsync Foundry (will run installer)..."
  read -r -p "Proceed with automatic install of ZKsync Foundry? [y/N]: " yn
  case "$yn" in
    [Yy]*)
      curl -L "$FOUNDARY_ZKSYNC_INSTALL_URL" | bash || err "Installation failed. Run the installer manually."
      export PATH="$HOME/.foundry/bin:$PATH"
      ;;
    *) err "ZKsync Foundry is required. Aborting." ;;
  esac
fi

# confirm zksync-capable forge (optional check)
if ! forge --version 2>/dev/null | grep -qi "zksync"; then
  info "Warning: 'forge' does not identify as zksync fork. You may still proceed but --zksync flags will fail."
fi

# ---------------------------
# 3. Load .env
# ---------------------------
if [ -f .env ]; then
  # shellcheck disable=SC1091
  source .env
  info "Loaded .env"
else
  err ".env file not found in the current directory. Please create one with RPC URLs and keys."
fi

# ---------------------------
# 4. Validate required env vars
# ---------------------------
REQUIRED_ENV=(ZKSYNC_SEPOLIA_RPC_URL SEPOLIA_RPC_URL UPDRAFT_PRIVATE_KEY)
for v in "${REQUIRED_ENV[@]}"; do
  if [ -z "${!v:-}" ]; then
    err "Environment var '$v' is not set or empty. Add it to .env and re-run."
  fi
done

# ---------------------------
# 5. Ensure updraft wallet exists or import from UPDRAFT_PRIVATE_KEY
# ---------------------------
if ! cast wallet list | grep -qw updraft; then
  info "Wallet 'updraft' not found in cast. Importing from UPDRAFT_PRIVATE_KEY..."
  # import wallet non-interactively (private key from .env)
  printf "%s\n" "$UPDRAFT_PRIVATE_KEY" | cast wallet import updraft --private-key --silent || err "Failed to import wallet 'updraft'."
  info "Imported 'updraft' to cast wallet list."
fi

# confirm wallet address
UPDRAFT_ADDR=$(cast wallet address --account updraft)
info "Using updraft address: $UPDRAFT_ADDR"

# ---------------------------
# 6. Set defaults (only set variables that may not be in .env)
# ---------------------------
for kv in "${DEFAULTS[@]}"; do
  name=${kv%%=*}
  val=${kv#*=}
  if [ -z "${!name:-}" ]; then
    eval "$name=\"$val\""
  fi
done

# ---------------------------
# 7. Helper: run forge create and capture deployed address
# ---------------------------
deploy_contract() {
  local target=$1   # e.g. src/RebaseToken.sol:RebaseToken
  shift
  info "Deploying $target ..."
  # assume zksync fork supports --zksync flag; if not, user installed wrong forge
  out=$(forge create "$target" --rpc-url "${ZKSYNC_SEPOLIA_RPC_URL}" --account updraft --legacy --zksync "$@" 2>&1) || {
    echo "$out"
    err "forge create failed for $target"
  }
  echo "$out" | awk '/Deployed to:/ {print $3}'
}

# ---------------------------
# 8. Deploy to ZKsync
# ---------------------------
ZKSYNC_REBASE_TOKEN_ADDRESS=$(deploy_contract "src/RebaseToken.sol:RebaseToken")
if [ -z "$ZKSYNC_REBASE_TOKEN_ADDRESS" ]; then err "Could not obtain ZKsync rebase token address."; fi
info "ZKsync RebaseToken deployed at $ZKSYNC_REBASE_TOKEN_ADDRESS"

ZKSYNC_POOL_ADDRESS=$(deploy_contract "src/RebaseTokenPool.sol:RebaseTokenPool" --constructor-args "$ZKSYNC_REBASE_TOKEN_ADDRESS" "[]" "$ZKSYNC_RNM_PROXY_ADDRESS" "$ZKSYNC_ROUTER")
if [ -z "$ZKSYNC_POOL_ADDRESS" ]; then err "Could not obtain ZKsync pool address."; fi
info "ZKsync Pool deployed at $ZKSYNC_POOL_ADDRESS"

# ---------------------------
# 9. Set permissions on ZKsync
# ---------------------------
info "Granting mint/burn role to pool..."
cast send "$ZKSYNC_REBASE_TOKEN_ADDRESS" --rpc-url "${ZKSYNC_SEPOLIA_RPC_URL}" --account updraft "grantMintAndBurnRole(address)" "$ZKSYNC_POOL_ADDRESS" || err "Failed to grant MintAndBurnRole"

info "Registering admin via owner and accepting admin role..."
cast send "$ZKSYNC_REGISTRY_MODULE_OWNER_CUSTOM" "registerAdminViaOwner(address)" "$ZKSYNC_REBASE_TOKEN_ADDRESS" --rpc-url "${ZKSYNC_SEPOLIA_RPC_URL}" --account updraft || err "registerAdminViaOwner failed"
cast send "$ZKSYNC_TOKEN_ADMIN_REGISTRY" "acceptAdminRole(address)" "$ZKSYNC_REBASE_TOKEN_ADDRESS" --rpc-url "${ZKSYNC_SEPOLIA_RPC_URL}" --account updraft || err "acceptAdminRole failed"
cast send "$ZKSYNC_TOKEN_ADMIN_REGISTRY" "setPool(address,address)" "$ZKSYNC_REBASE_TOKEN_ADDRESS" "$ZKSYNC_POOL_ADDRESS" --rpc-url "${ZKSYNC_SEPOLIA_RPC_URL}" --account updraft || err "setPool failed"

# ---------------------------
# 10. Deploy to Sepolia via forge script
# ---------------------------
info "Deploying contracts on Sepolia via forge script (TokenAndPoolDeployer)..."
sep_out=$(forge script ./script/Deployer.s.sol:TokenAndPoolDeployer --rpc-url "${SEPOLIA_RPC_URL}" --account updraft --broadcast 2>&1) || {
  echo "$sep_out"
  err "Sepolia deploy script failed"
}
info "Sepolia deploy script completed."

SEPOLIA_REBASE_TOKEN_ADDRESS=$(echo "$sep_out" | grep -Eo "token: contract RebaseToken [0-9xa-fA-F]+" | awk '{print $NF}' || true)
SEPOLIA_POOL_ADDRESS=$(echo "$sep_out" | grep -Eo "pool: contract RebaseTokenPool [0-9xa-fA-F]+" | awk '{print $NF}' || true)

info "Sepolia rebase token: ${SEPOLIA_REBASE_TOKEN_ADDRESS:-<not found>}"
info "Sepolia pool: ${SEPOLIA_POOL_ADDRESS:-<not found>}"

# ---------------------------
# 11. Deploy Vault on Sepolia
# ---------------------------
info "Deploying vault on Sepolia..."
vault_out=$(forge script ./script/Deployer.s.sol:VaultDeployer --rpc-url "${SEPOLIA_RPC_URL}" --account updraft --broadcast --sig "run(address)" "$SEPOLIA_REBASE_TOKEN_ADDRESS" 2>&1) || {
  echo "$vault_out"
  err "Vault deploy failed"
}
VAULT_ADDRESS=$(echo "$vault_out" | grep -i "vault: contract Vault" | awk '{print $NF}' || true)
info "Vault: ${VAULT_ADDRESS:-<not found>}"

# ---------------------------
# 12. Configure pool on Sepolia (example)
# ---------------------------
info "Configuring pool on Sepolia..."
forge script ./script/ConfigurePool.s.sol:ConfigurePoolScript --rpc-url "${SEPOLIA_RPC_URL}" --account updraft --broadcast --sig "run(address,uint64,address,address,bool,uint128,uint128,bool,uint128,uint128)" \
  "${SEPOLIA_POOL_ADDRESS}" "${ZKSYNC_SEPOLIA_CHAIN_SELECTOR}" "${ZKSYNC_POOL_ADDRESS}" "${ZKSYNC_REBASE_TOKEN_ADDRESS}" false 0 0 false 0 0 || err "ConfigurePool script failed"

# ---------------------------
# 13. Deposit to vault
# ---------------------------
info "Depositing funds to the vault on Sepolia..."
cast send "${VAULT_ADDRESS}" --value "${AMOUNT}" --rpc-url "${SEPOLIA_RPC_URL}" --account updraft "deposit()" || err "Deposit failed"

# ---------------------------
# 14. Configure pool on ZKsync (applyChainUpdates)
# ---------------------------
info "Configuring pool on ZKsync..."
# build the applyChainUpdates payload carefully - this may require manual tuning for your exact contract ABI
apply_payload="[${SEPOLIA_CHAIN_SELECTOR}]"
apply_updates="[(${SEPOLIA_CHAIN_SELECTOR},[$(cast abi-encode "f(address)" "${SEPOLIA_POOL_ADDRESS}")],$(cast abi-encode "f(address)" "${SEPOLIA_REBASE_TOKEN_ADDRESS}"),(false,0,0),(false,0,0))]"
cast send "${ZKSYNC_POOL_ADDRESS}" --rpc-url "${ZKSYNC_SEPOLIA_RPC_URL}" --account updraft "applyChainUpdates(uint64[],(uint64,bytes[],bytes,(bool,uint128,uint128),(bool,uint128,uint128))[])" "${apply_payload}" "${apply_updates}" || err "applyChainUpdates failed"

# ---------------------------
# 15. Bridge tokens (example using a forge script)
# ---------------------------
info "Checking Sepolia balance before bridging..."
SEPOLIA_BALANCE_BEFORE=$(cast balance "$(cast wallet address --account updraft)" --erc20 "${SEPOLIA_REBASE_TOKEN_ADDRESS}" --rpc-url "${SEPOLIA_RPC_URL}" || true)
info "Sepolia balance before bridging: ${SEPOLIA_BALANCE_BEFORE:-0}"

info "Running BridgeTokens script..."
forge script ./script/BridgeTokens.s.sol:BridgeTokensScript --rpc-url "${SEPOLIA_RPC_URL}" --account updraft --broadcast --sig "sendMessage(address,uint64,address,uint256,address,address)" \
  "$(cast wallet address --account updraft)" "${ZKSYNC_SEPOLIA_CHAIN_SELECTOR}" "${SEPOLIA_REBASE_TOKEN_ADDRESS}" "${AMOUNT}" "${SEPOLIA_LINK_ADDRESS}" "${SEPOLIA_ROUTER}" || err "Bridge script failed"

SEPOLIA_BALANCE_AFTER=$(cast balance "$(cast wallet address --account updraft)" --erc20 "${SEPOLIA_REBASE_TOKEN_ADDRESS}" --rpc-url "${SEPOLIA_RPC_URL}" || true)
info "Sepolia balance after bridging: ${SEPOLIA_BALANCE_AFTER:-0}"

info "🎉 Script finished successfully."

# End of script
