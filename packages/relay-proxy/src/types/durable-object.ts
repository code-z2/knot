import { Hex } from 'viem';

export type DORequestHandler = <Result>(userId: string, path: string, init?: RequestInit) => Promise<Result>;

export type DOResponse<Result> =
    | {
          ok: true;
          result: Result;
      }
    | {
          ok: false;
          reason: string;
      };

export type FaucetDOResult = {
    funded: boolean;
    hashes: Record<number, Hex>;
};

export type GasTankDORecord = {
    pendingExposureUsdc: Hex;
};
