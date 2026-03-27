import { Authentication, Registration } from 'webauthx/server';

/**
 * Verified App Attest material that must be persisted for future assertion
 * checks.
 */
export type AppAttestationVerification = {
    environment: 'development' | 'production';
    keyId: string;
    publicKey: string;
};

/**
 * App Attest verification surface used by auth routes and middleware.
 */
export type AppAttestVerifier = {
    verifyAssertion: (input: {
        assertion: string;
        keyId: string;
        payload: string;
        publicKey: string;
        signCount: number;
    }) => {
        signCount: number;
    };
    verifyAttestation: (input: {
        attestation: string;
        challenge: string;
        keyId: string;
    }) => AppAttestationVerification;
};

/**
 * Passkey/WebAuthn verification surface used by register/login routes.
 */
export type PasskeyVerifier = {
    getAuthenticationOptions: (credentialId: string, challenge: string) => Authentication.Options;
    getRegistrationOptions: (userId: string, challenge: string) => Registration.Options;
    verifyAuthentication: (input: {
        challenge: string;
        publicKey: string;
        response: Authentication.Response;
    }) => boolean;
    verifyRegistration: (input: {
        challenge: string;
        credential: Registration.Credential;
    }) => Registration.Response;
};
