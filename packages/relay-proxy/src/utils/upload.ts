import { UploadPurpose } from '@/types';
import { generateUUID } from './auth';

export function parseBoundedInteger(
    value: string | undefined,
    min: number,
    max: number,
    fallback: number,
) {
    const parsed = Number.parseInt(value ?? '', 10);

    if (!Number.isFinite(parsed) || parsed < min || parsed > max) {
        return fallback;
    }

    return parsed;
}

export function createTimestamp() {
    return new Date().toISOString().replace(/[-:.TZ]/g, '');
}

export function createImageID(input: { fileName: string; purpose: UploadPurpose; userId: string }) {
    return `images/${input.purpose}/${input.userId}/${createTimestamp()}-${generateUUID()}-${input.fileName}`;
}
