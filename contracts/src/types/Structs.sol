// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

struct Call {
    address target;
    uint256 value;
    bytes data;
}

struct ChainCalls {
    uint256 chainId;
    Call[] calls;
}

enum JobStatus {
    Accumulating,
    Accumulated,
    Executed,
    Refunded
}

struct JobState {
    uint256 received;
    bool approved;
    JobStatus status;
    address inputToken;
    uint256[] sourceChains;
}
