export type RpcErrorDetail = {
    message: string;
    path: string;
};

export type RpcAppErrorDefinition = {
    code: number;
    reason: string;
    status: 400 | 401 | 500;
};
