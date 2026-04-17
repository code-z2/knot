import { Authentication, Registration } from 'webauthx/server';
import type { RpcEnvelope } from '../rpc';

export type UserRegisterOptionsParams = {
    userId: string;
};

export type UserRegisterOptionsRequest = RpcEnvelope<'knot_userRegisterOptions', UserRegisterOptionsParams>;

export type UserRegisterOptionsResult = {
    appAttestChallenge: string;
    challengeId: string;
    options: Registration.Options;
};

export type UserRegisterVerifyParams = {
    appAttestKeyId: string;
    attestation: string;
    challengeId: string;
    credential: Registration.Credential;
};

export type UserRegisterVerifyRequest = RpcEnvelope<'knot_userRegisterVerify', UserRegisterVerifyParams>;

export type UserLoginOptionsParams = {
    credentialId: string;
};

export type UserLoginOptionsRequest = RpcEnvelope<'knot_userLoginOptions', UserLoginOptionsParams>;

export type UserLoginOptionsResult = {
    appAttestChallenge: string;
    challengeId: string;
    options: Authentication.Options;
};

export type UserLoginVerifyParams = {
    appAttestAssertion: string;
    appAttestKeyId: string;
    challengeId: string;
    response: Authentication.Response;
};

export type UserLoginVerifyRequest = RpcEnvelope<'knot_userLoginVerify', UserLoginVerifyParams>;

export type UserLogoutParams = Record<string, never>;

export type UserLogoutRequest = RpcEnvelope<'knot_userLogout', UserLogoutParams>;
