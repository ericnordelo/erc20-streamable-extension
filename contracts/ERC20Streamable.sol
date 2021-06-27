// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./StreamingManager.sol";
import "./Structs.sol";

abstract contract ERC20Streamable is ERC20, AccessControl {
    using Counters for Counters.Counter;

    Counters.Counter private _streamingIds;

    bytes32 public constant ADMIN = keccak256("admin");

    address public streamingManagerAddress;
    StreamingManager private _streamingManager;

    mapping(address => mapping(address => bool)) private _openStreamings;
    mapping(uint256 => Streaming) private _streamings;
    mapping(address => FlowInfo) private _incomingFlows;
    mapping(address => FlowInfo) private _outgoingFlows;

    event StreamingCreated(address indexed from, address indexed to, uint256 indexed id, uint64 endingDate);
    event StreamingStopped(address indexed from, address indexed to);
    event StreamingUpdated(address indexed from, address indexed to, uint256 indexed id, uint64 endingDate);

    constructor() {
        // The super admin is the deployer
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _setupRole(ADMIN, msg.sender);
    }

    function setStreamingManagerAddress(address _streamingManagerAddress) external onlyRole(ADMIN) {
        streamingManagerAddress = _streamingManagerAddress;
        _streamingManager = StreamingManager(_streamingManagerAddress);
    }

    modifier isValidStreaming(Streaming memory _streaming) {
        require(
            keccak256(abi.encodePacked((_streaming.stype))) == keccak256(abi.encodePacked(("classic"))),
            "Invalid type of open streamings"
        );
        require(_streaming.senderAddress == msg.sender, "Invalid sender");
        require(_streaming.receiverAddress != address(0), "Invalid receiver");
        require(_streaming.amountPerSecond > 0, "Invalid amount per second");
        require(_streaming.startingDate < _streaming.endingDate, "Invalid duration interval");
        _;
    }

    function checkOnlySenderOrAdmin(address _sender) internal view {
        require(_sender == msg.sender || hasRole(ADMIN, msg.sender), "Permission denied");
    }

    // creates one streaming
    function createStreaming(Streaming memory _streaming) external isValidStreaming(_streaming) {
        require(block.timestamp < _streaming.endingDate, "Invalid ending date");
        require(
            _openStreamings[_streaming.senderAddress][_streaming.receiverAddress],
            "Can't open two streams to same address"
        );
        _streaming.startingDate = uint64(block.timestamp);

        uint256 totalAmount = _streaming.amountPerSecond * (_streaming.endingDate - _streaming.startingDate);

        // should have enough balance to open the streaming
        require(totalAmount <= balanceOf(msg.sender), "Not enough balance");

        _streamingIds.increment();
        uint256 newStreamingId = _streamingIds.current();

        _streamings[newStreamingId] = _streaming;
        _openStreamings[_streaming.senderAddress][_streaming.receiverAddress] = true;

        // update flows
        _incomingFlows[_streaming.receiverAddress].flow.amountPerSecond += _streaming.amountPerSecond;
        _outgoingFlows[_streaming.senderAddress].flow.amountPerSecond += _streaming.amountPerSecond;

        // update flow infos
        FlowInfo memory incomingFlowInfo = _incomingFlows[_streaming.receiverAddress];
        FlowInfo memory outgoingFlowInfo = _outgoingFlows[_streaming.senderAddress];

        if (incomingFlowInfo.flow.startingDate == 0) {
            _incomingFlows[_streaming.receiverAddress].flow.startingDate = _streaming.startingDate;
        } else {
            _incomingFlows[_streaming.receiverAddress].totalPreviousValueGenerated +=
                (_streaming.startingDate - incomingFlowInfo.flow.startingDate) *
                incomingFlowInfo.flow.amountPerSecond;

            _incomingFlows[_streaming.receiverAddress].flow.startingDate = _streaming.startingDate;
        }
        if (outgoingFlowInfo.flow.startingDate == 0) {
            _outgoingFlows[_streaming.senderAddress].flow.startingDate = _streaming.startingDate;
        } else {
            _outgoingFlows[_streaming.senderAddress].totalPreviousValueGenerated +=
                (_streaming.startingDate - outgoingFlowInfo.flow.startingDate) *
                outgoingFlowInfo.flow.amountPerSecond;

            _outgoingFlows[_streaming.senderAddress].flow.startingDate = _streaming.startingDate;
        }

        // transfer the total amount to the manager
        transfer(streamingManagerAddress, totalAmount);

        emit StreamingCreated(
            _streaming.senderAddress,
            _streaming.receiverAddress,
            newStreamingId,
            _streaming.endingDate
        );
    }

    function updateStreaming(uint256 _streamingId, StreamingUpdateRequest calldata _streamingUpdateRequest)
        external
    {
        Streaming memory streaming = getStreaming(_streamingId);
        uint256 currentTimestamp = block.timestamp;
        if (
            streaming.startingDate >= _streamingUpdateRequest.endingDate ||
            _streamingUpdateRequest.endingDate <= currentTimestamp ||
            streaming.senderAddress != msg.sender ||
            _streamingUpdateRequest.amountPerSecond <= 0
        ) {
            revert("Invalid request");
        }

        if (streaming.endingDate <= currentTimestamp) {
            _stop(streaming, _streamingId);
        } else {
            uint256 quantityToPayToReceiver;

            if (currentTimestamp > streaming.startingDate) {
                uint256 intervalTranscursed = currentTimestamp - streaming.startingDate;
                quantityToPayToReceiver = ((streaming.amountPerSecond * intervalTranscursed));
                streaming.startingDate = uint64(currentTimestamp);
            }

            // calculate how much should streaming manager hold now and update
            uint256 currentHolding = (streaming.amountPerSecond *
                (streaming.endingDate - streaming.startingDate)) - quantityToPayToReceiver;
            uint256 expectedHolding = _streamingUpdateRequest.amountPerSecond *
                (_streamingUpdateRequest.endingDate - streaming.startingDate);

            // update flow infos
            FlowInfo memory incomingFlowInfo = _incomingFlows[streaming.receiverAddress];
            FlowInfo memory outgoingFlowInfo = _outgoingFlows[streaming.senderAddress];

            _incomingFlows[streaming.receiverAddress].totalPreviousValueGenerated +=
                (currentTimestamp - incomingFlowInfo.flow.startingDate) *
                incomingFlowInfo.flow.amountPerSecond;

            _incomingFlows[streaming.receiverAddress].flow.startingDate = uint64(currentTimestamp);

            _outgoingFlows[streaming.senderAddress].totalPreviousValueGenerated +=
                (currentTimestamp - outgoingFlowInfo.flow.startingDate) *
                outgoingFlowInfo.flow.amountPerSecond;

            _outgoingFlows[streaming.senderAddress].flow.startingDate = uint64(currentTimestamp);

            if (quantityToPayToReceiver > 0) {
                _incomingFlows[streaming.receiverAddress]
                .totalPreviousValueTransfered += quantityToPayToReceiver;
                _outgoingFlows[streaming.senderAddress]
                .totalPreviousValueTransfered += quantityToPayToReceiver;
            }

            // update flows
            _incomingFlows[streaming.receiverAddress].flow.amountPerSecond =
                _incomingFlows[streaming.receiverAddress].flow.amountPerSecond -
                streaming.amountPerSecond +
                _streamingUpdateRequest.amountPerSecond;
            _outgoingFlows[streaming.senderAddress].flow.amountPerSecond =
                _outgoingFlows[streaming.senderAddress].flow.amountPerSecond -
                streaming.amountPerSecond +
                _streamingUpdateRequest.amountPerSecond;

            // update the streaming
            _streamings[_streamingId].startingDate = uint64(currentTimestamp);
            _streamings[_streamingId].amountPerSecond = _streamingUpdateRequest.amountPerSecond;
            _streamings[_streamingId].endingDate = _streamingUpdateRequest.endingDate;

            // make the transfers (the payment and the return)
            if (quantityToPayToReceiver > 0) {
                _streamingManager.transfer(streaming.receiverAddress, quantityToPayToReceiver);
            }
            // update streaming manager balance
            if (currentHolding > expectedHolding) {
                _streamingManager.transfer(streaming.senderAddress, expectedHolding - currentHolding);
            } else if (currentHolding < expectedHolding) {
                transfer(streamingManagerAddress, currentHolding - expectedHolding);
            }

            emit StreamingUpdated(
                streaming.senderAddress,
                streaming.receiverAddress,
                _streamingId,
                _streamingUpdateRequest.endingDate
            );
        }
    }

    // stop a streaming (protected against reentracy by check-effect-interactions pattern)
    function stopStreaming(uint256 _streamingId) external {
        Streaming memory streaming = getStreaming(_streamingId);

        checkOnlySenderOrAdmin(streaming.senderAddress);

        _stop(streaming, _streamingId);
    }

    // getters by id
    function getStreaming(uint256 _streamingId) public view returns (Streaming memory) {
        require(_streamings[_streamingId].amountPerSecond > 0, "Query for unexisting streaming");
        return _streamings[_streamingId];
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        uint256 notYetPaidIncomingFlow = _incomingFlows[account].totalPreviousValueGenerated -
            _incomingFlows[account].totalPreviousValueTransfered;
        uint256 notYetPaidOutgoingFlow = _outgoingFlows[account].totalPreviousValueGenerated -
            _outgoingFlows[account].totalPreviousValueTransfered;
        return super.balanceOf(account) + notYetPaidIncomingFlow - notYetPaidOutgoingFlow;
    }

    function _stop(Streaming memory streaming, uint256 _streamingId) internal {
        // update the balance of the receiver (pay what you owe)

        // this must be true always
        assert(streaming.startingDate < streaming.endingDate);

        uint256 quantityToPay;
        uint256 quantityToReturn;

        if (block.timestamp > streaming.startingDate) {
            uint256 totalAmount = streaming.amountPerSecond * (streaming.endingDate - streaming.startingDate);

            uint256 addTillDate = streaming.endingDate < block.timestamp
                ? streaming.endingDate
                : block.timestamp;
            uint256 intervalTranscursed = addTillDate - streaming.startingDate;

            quantityToPay = ((streaming.amountPerSecond * intervalTranscursed));
            quantityToReturn = totalAmount - quantityToPay;
        }

        // stop the streaming
        delete _streamings[_streamingId];
        _openStreamings[streaming.senderAddress][streaming.receiverAddress] = false;

        // update flows
        _incomingFlows[streaming.receiverAddress].flow.amountPerSecond -= streaming.amountPerSecond;
        _outgoingFlows[streaming.senderAddress].flow.amountPerSecond -= streaming.amountPerSecond;

        // update flow infos
        FlowInfo memory incomingFlowInfo = _incomingFlows[streaming.receiverAddress];
        FlowInfo memory outgoingFlowInfo = _outgoingFlows[streaming.senderAddress];

        _incomingFlows[streaming.receiverAddress].totalPreviousValueGenerated +=
            (streaming.startingDate - incomingFlowInfo.flow.startingDate) *
            incomingFlowInfo.flow.amountPerSecond;

        _incomingFlows[streaming.receiverAddress].flow.startingDate = streaming.startingDate;

        _outgoingFlows[streaming.senderAddress].totalPreviousValueGenerated +=
            (streaming.startingDate - outgoingFlowInfo.flow.startingDate) *
            outgoingFlowInfo.flow.amountPerSecond;

        _outgoingFlows[streaming.senderAddress].flow.startingDate = streaming.startingDate;

        if (quantityToPay > 0) {
            _incomingFlows[streaming.receiverAddress].totalPreviousValueTransfered += quantityToPay;
            _outgoingFlows[streaming.senderAddress].totalPreviousValueTransfered += quantityToPay;
        }

        // make the transfers (the payment and the return)
        if (quantityToPay > 0) {
            _streamingManager.transfer(streaming.receiverAddress, quantityToPay);
        }
        if (quantityToReturn > 0) {
            _streamingManager.transfer(streaming.receiverAddress, quantityToReturn);
        }

        emit StreamingStopped(streaming.senderAddress, streaming.receiverAddress);
    }

    function _beforeTokenTransfer(
        address from,
        address,
        uint256 amount
    ) internal view virtual override {
        // address 0 is minting
        if (from != address(0) && super.balanceOf(from) < amount) {
            revert("Real balance (wihtout streamings) not enough to transfer");
        }
    }
}
