export async function readJson<type = unknown>(response: Response) {
    return await response.json() as type;
}

export function jsonHeaders(headers: HeadersInit = {}) {
    return {
        'content-type': 'application/json',
        ...headers,
    };
}
