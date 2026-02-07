package main

import (
	"context"
	"crypto/ecdsa"
	"encoding/json"
	"log"
	"math/big"
	"net/http"
	"sync"
	"time"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

// ---------------------------------------------------------------------------
// Testnet USDC addresses (Circle official, all 6 decimals)
// ---------------------------------------------------------------------------

type chainToken struct {
	chainID      uint64
	tokenAddress common.Address
	amount       *big.Int // base units (6 decimals for USDC)
}

var testnetUSDCTransfers = []chainToken{
	{chainID: 11155111, tokenAddress: common.HexToAddress("0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"), amount: big.NewInt(2_000_000)}, // 2 USDC Sepolia
	{chainID: 84532, tokenAddress: common.HexToAddress("0x036CbD53842c5426634e7929541eC2318f3dCF7e"), amount: big.NewInt(2_000_000)},   // 2 USDC Base Sepolia
	{chainID: 421614, tokenAddress: common.HexToAddress("0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d"), amount: big.NewInt(2_000_000)},  // 2 USDC Arb Sepolia
}

// 0.01 ETH in wei
var ethDripAmount = new(big.Int).SetUint64(10_000_000_000_000_000)

// ERC20 transfer(address,uint256) selector: 0xa9059cbb
var erc20TransferSelector = crypto.Keccak256([]byte("transfer(address,uint256)"))[:4]

// ---------------------------------------------------------------------------
// Request / Response
// ---------------------------------------------------------------------------

type faucetRequest struct {
	EOAAddress string `json:"eoaAddress"`
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

func (s *server) handleFaucetFund(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, map[string]string{"error": "Method not allowed"})
		return
	}

	if err := s.authorize(r); err != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "Unauthorized"})
		return
	}

	if s.cfg.faucetPrivateKey == "" {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"error": "Faucet not configured"})
		return
	}

	var req faucetRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid JSON body"})
		return
	}

	if !eoaPattern.MatchString(req.EOAAddress) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid EOA address"})
		return
	}

	// Respond immediately; fund in background.
	go s.fundAccount(req.EOAAddress)

	writeJSON(w, http.StatusAccepted, map[string]string{"status": "funding_initiated"})
}

// ---------------------------------------------------------------------------
// Background funding
// ---------------------------------------------------------------------------

func (s *server) fundAccount(recipientHex string) {
	privKey, err := crypto.HexToECDSA(s.cfg.faucetPrivateKey)
	if err != nil {
		log.Printf("faucet: failed to parse private key: %v", err)
		return
	}

	sender := crypto.PubkeyToAddress(privKey.PublicKey)
	recipient := common.HexToAddress(recipientHex)

	var wg sync.WaitGroup
	for chainID, rpcURL := range s.cfg.faucetRPCURLs {
		wg.Add(1)
		go func(chainID uint64, rpcURL string) {
			defer wg.Done()
			s.fundOnChain(chainID, rpcURL, privKey, sender, recipient)
		}(chainID, rpcURL)
	}
	wg.Wait()
	log.Printf("faucet: funding complete for %s", recipientHex)
}

func (s *server) fundOnChain(
	chainID uint64,
	rpcURL string,
	privKey *ecdsa.PrivateKey,
	sender, recipient common.Address,
) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	client, err := ethclient.DialContext(ctx, rpcURL)
	if err != nil {
		log.Printf("faucet: chain %d: dial failed: %v", chainID, err)
		return
	}
	defer client.Close()

	nonce, err := client.PendingNonceAt(ctx, sender)
	if err != nil {
		log.Printf("faucet: chain %d: nonce failed: %v", chainID, err)
		return
	}

	gasPrice, err := client.SuggestGasPrice(ctx)
	if err != nil {
		log.Printf("faucet: chain %d: gas price failed: %v", chainID, err)
		return
	}

	signer := types.NewEIP155Signer(new(big.Int).SetUint64(chainID))

	// --- ERC20 USDC transfer ---
	for _, t := range testnetUSDCTransfers {
		if t.chainID != chainID {
			continue
		}
		calldata := encodeERC20Transfer(recipient, t.amount)
		tx := types.NewTx(&types.LegacyTx{
			Nonce:    nonce,
			GasPrice: gasPrice,
			Gas:      65_000,
			To:       &t.tokenAddress,
			Value:    big.NewInt(0),
			Data:     calldata,
		})

		signed, err := types.SignTx(tx, signer, privKey)
		if err != nil {
			log.Printf("faucet: chain %d: USDC sign failed: %v", chainID, err)
			return
		}
		if err := client.SendTransaction(ctx, signed); err != nil {
			log.Printf("faucet: chain %d: USDC send failed: %v", chainID, err)
		} else {
			log.Printf("faucet: chain %d: USDC tx %s", chainID, signed.Hash().Hex())
		}
		nonce++
	}

	// --- ETH transfer ---
	to := recipient
	tx := types.NewTx(&types.LegacyTx{
		Nonce:    nonce,
		GasPrice: gasPrice,
		Gas:      21_000,
		To:       &to,
		Value:    ethDripAmount,
		Data:     nil,
	})

	signed, err := types.SignTx(tx, signer, privKey)
	if err != nil {
		log.Printf("faucet: chain %d: ETH sign failed: %v", chainID, err)
		return
	}
	if err := client.SendTransaction(ctx, signed); err != nil {
		log.Printf("faucet: chain %d: ETH send failed: %v", chainID, err)
	} else {
		log.Printf("faucet: chain %d: ETH tx %s", chainID, signed.Hash().Hex())
	}
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

// encodeERC20Transfer builds calldata for ERC20.transfer(address,uint256).
// Layout: 4-byte selector + 32-byte address (left-padded) + 32-byte amount (left-padded) = 68 bytes.
func encodeERC20Transfer(to common.Address, amount *big.Int) []byte {
	data := make([]byte, 68)
	copy(data[0:4], erc20TransferSelector)
	copy(data[4+12:4+32], to.Bytes()) // address is 20 bytes, left-padded to 32
	amountBytes := amount.Bytes()
	copy(data[36+(32-len(amountBytes)):68], amountBytes)
	return data
}
