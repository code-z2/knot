-include .env.local

# Helper to verify deployment
# usage: make verify-contract CHAIN_ID=11155111 ADDRESS=0x... ARGS="0x..."
verify-contract:
	forge verify-contract --chain-id $(CHAIN_ID) --watch $(ADDRESS) src/AccumulatorFactory.sol:AccumulatorFactory --constructor-args $(ARGS) --etherscan-api-key $(ETHERSCAN_API_KEY)

# ==============================================================================
# LIMITED TESTNET DEPLOYMENT
# ==============================================================================

deploy-limited-testnet: deploy-sepolia deploy-base-sepolia deploy-arbitrum-sepolia

deploy-sepolia:
	@echo "Deploying to Sepolia..."
	forge script script/DeployTestnet.s.sol:DeployTestnet --rpc-url $(SEPOLIA_RPC_URL) --broadcast --verify --verifier blockscout --verifier-url $(SEPOLIA_BLOCKSCOUT_URL) -vvvv

deploy-base-sepolia:
	@echo "Deploying to Base Sepolia..."
	forge script script/DeployTestnet.s.sol:DeployTestnet --rpc-url $(BASE_SEPOLIA_RPC_URL) --broadcast --verify --verifier blockscout --verifier-url $(BASE_SEPOLIA_BLOCKSCOUT_URL) -vvvv

deploy-arbitrum-sepolia:
	@echo "Deploying to Arbitrum Sepolia..."
	forge script script/DeployTestnet.s.sol:DeployTestnet --rpc-url $(ARBITRUM_SEPOLIA_RPC_URL) --broadcast --verify --verifier blockscout --verifier-url $(ARBITRUM_SEPOLIA_BLOCKSCOUT_URL) -vvvv

# ==============================================================================
# LIMITED MAINNET DEPLOYMENT
# ==============================================================================

deploy-limited-mainnet: deploy-arbitrum deploy-base deploy-polygon

deploy-arbitrum:
	@echo "Deploying to Arbitrum..."
	forge script script/DeployMainnet.s.sol:DeployMainnet --rpc-url $(ARBITRUM_RPC_URL) --broadcast --verify --verifier blockscout --verifier-url $(ARBITRUM_BLOCKSCOUT_URL) -vvvv

deploy-base:
	@echo "Deploying to Base..."
	forge script script/DeployMainnet.s.sol:DeployMainnet --rpc-url $(BASE_RPC_URL) --broadcast --verify --verifier blockscout --verifier-url $(BASE_BLOCKSCOUT_URL) -vvvv

deploy-polygon:
	@echo "Deploying to Polygon..."
	forge script script/DeployMainnet.s.sol:DeployMainnet --rpc-url $(POLYGON_RPC_URL) --broadcast --verify --verifier blockscout --verifier-url $(POLYGON_BLOCKSCOUT_URL) -vvvv
