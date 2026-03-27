export type AuthFidelity = 'high' | 'low';

export type AuthConfig = {
    appAttestAllowDevelopment: boolean;
    appBundleId: string;
    appTeamId: string;
    rpId: string;
    rpName: string;
    rpOrigin: string;
};
