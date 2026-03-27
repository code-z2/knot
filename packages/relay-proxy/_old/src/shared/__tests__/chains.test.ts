import { describe, expect, it } from 'vitest';

import { BadRequestError } from '../errors';
import { ALL_KNOWN_CHAINS, extractKnownChain, FAUCET_CHAINS } from '../chains';

// ---------------------------------------------------------------------------
// ALL_KNOWN_CHAINS
// ---------------------------------------------------------------------------

describe('ALL_KNOWN_CHAINS', () => {
    it('contains entries', () => {
        expect(ALL_KNOWN_CHAINS.length).toBeGreaterThan(0);
    });

    it('every entry has id and rpcUrls', () => {
        for (const chain of ALL_KNOWN_CHAINS) {
            expect(chain).toHaveProperty('id');
            expect(chain).toHaveProperty('rpcUrls');
        }
    });

    it('includes Ethereum mainnet (1)', () => {
        expect(ALL_KNOWN_CHAINS.some((c) => c.id === 1)).toBe(true);
    });

    it('includes Sepolia (11155111)', () => {
        expect(ALL_KNOWN_CHAINS.some((c) => c.id === 11155111)).toBe(true);
    });

    it('includes Base (8453)', () => {
        expect(ALL_KNOWN_CHAINS.some((c) => c.id === 8453)).toBe(true);
    });
});

// ---------------------------------------------------------------------------
// FAUCET_CHAINS
// ---------------------------------------------------------------------------

describe('FAUCET_CHAINS', () => {
    it('contains exactly the expected testnets', () => {
        const ids = FAUCET_CHAINS.map((c) => c.id);
        expect(ids).toContain(11155111); // Sepolia
        expect(ids).toContain(84532); // Base Sepolia
        expect(ids).toContain(421614); // Arbitrum Sepolia
        expect(ids).toHaveLength(3);
    });
});

// ---------------------------------------------------------------------------
// extractKnownChain
// ---------------------------------------------------------------------------

describe('extractKnownChain', () => {
    it('resolves Ethereum mainnet', () => {
        const chain = extractKnownChain(1);
        expect(chain.id).toBe(1);
    });

    it('resolves Sepolia', () => {
        const chain = extractKnownChain(11155111);
        expect(chain.id).toBe(11155111);
    });

    it('resolves Arbitrum', () => {
        const chain = extractKnownChain(42161);
        expect(chain.id).toBe(42161);
    });

    it('resolves Base', () => {
        const chain = extractKnownChain(8453);
        expect(chain.id).toBe(8453);
    });

    it('returns Alchemy-enhanced chain with rpcUrls.alchemy', () => {
        const chain = extractKnownChain(1);
        const rpcUrls = chain.rpcUrls as Record<string, { http: readonly string[] }>;
        expect(rpcUrls.alchemy).toBeDefined();
        expect(rpcUrls.alchemy.http[0]).toContain('g.alchemy.com');
    });

    it('throws BadRequestError for unknown chain ID', () => {
        expect(() => extractKnownChain(999999)).toThrow(BadRequestError);
    });
});
