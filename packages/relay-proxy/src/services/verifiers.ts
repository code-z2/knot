import { decodeBase64Url } from 'hono/utils/encode';
import { verifyAssertion, verifyAttestation } from 'node-app-attest';
import { Authentication, Registration } from 'webauthx/server';
import type { AuthConfig, AppAttestVerifier, PasskeyVerifier } from '@/types';
import { stringToBytes, toHex } from 'viem';

/**
 * Wraps the App Attest library behind the relay-proxy verifier interface.
 */
export function createAppAttestVerifier(config: AuthConfig): AppAttestVerifier {
    return {
        verifyAssertion(input) {
            const result = verifyAssertion({
                assertion: decodeBase64Url(input.assertion),
                bundleIdentifier: config.appBundleId,
                payload: input.payload,
                publicKey: input.publicKey,
                signCount: input.signCount,
                teamIdentifier: config.appTeamId,
            });

            return {
                signCount: result.signCount,
            };
        },

        verifyAttestation(input) {
            const result = verifyAttestation({
                allowDevelopmentEnvironment: config.appAttestAllowDevelopment,
                attestation: decodeBase64Url(input.attestation),
                bundleIdentifier: config.appBundleId,
                challenge: input.challenge,
                keyId: input.keyId,
                teamIdentifier: config.appTeamId,
            });

            return {
                environment: result.environment as 'development' | 'production',
                keyId: result.keyId,
                publicKey: result.publicKey,
            };
        },
    };
}

/**
 * Wraps the passkey/WebAuthn library behind the relay-proxy verifier interface.
 */
export function createPasskeyVerifier(config: AuthConfig): PasskeyVerifier {
    return {
        getAuthenticationOptions(credentialId, challenge) {
            return Authentication.getOptions({
                challenge: toHex(challenge),
                credentialId,
                rpId: config.rpId,
            }).options;
        },

        getRegistrationOptions(userId, challenge) {
            return Registration.getOptions({
                challenge: toHex(challenge),
                rp: {
                    id: config.rpId,
                    name: config.rpName,
                },
                user: {
                    displayName: userId,
                    id: stringToBytes(userId),
                    name: userId,
                },
            }).options;
        },

        verifyAuthentication(input) {
            return Authentication.verify(input.response, {
                challenge: toHex(input.challenge),
                origin: config.rpOrigin,
                publicKey: toHex(input.publicKey),
                rpId: config.rpId,
            });
        },

        verifyRegistration(input) {
            return Registration.verify(input.credential, {
                challenge: toHex(input.challenge),
                origin: config.rpOrigin,
                rpId: config.rpId,
            });
        },
    };
}
