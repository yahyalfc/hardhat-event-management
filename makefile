# Simple Hardhat Makefile

.PHONY: compile test node deploy verify

compile:
	@echo "Compiling contracts..."
	npx hardhat compile

test:
	@echo "Running tests..."
	npx hardhat test

node:
	@echo "Starting local node..."
	npx hardhat node

deploy:
	@echo "Deploying to Sepolia..."
	npx hardhat run scripts/deploy.js --network sepolia

verify:
	@echo "Syntax => npx hardhat verify --network sepolia CONTRACT_ADDRESS"