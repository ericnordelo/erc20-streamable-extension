// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

struct Streaming {
    string stype;
    address senderAddress;
    address receiverAddress;
    uint256 amountPerSecond;
    uint64 startingDate;
    uint64 endingDate;
}

struct StreamingUpdateRequest {
    uint256 amountPerSecond;
    uint64 endingDate;
}

struct Flow {
    uint256 amountPerSecond;
    uint64 startingDate;
}

struct FlowInfo {
    Flow flow;
    uint256 totalPreviousValueGenerated;
    uint256 totalPreviousValueTransfered;
}
