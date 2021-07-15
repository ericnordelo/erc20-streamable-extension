// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ERC20Streamable.sol";
import "./StreamingManager.sol";
import "./Structs.sol";

/**
 * @title Library for streamings
 * @author Eric Nordelo
 */
library StreamingLibrary {
    /**
     * @notice Helper for streaming creation
     * @param _streaming The streaming being created
     * @param _incomingFlows The incoming flows mapping
     * @param _outgoingFlows The outgoing flows mapping
     */
    function createStreaming(
        Streaming memory _streaming,
        mapping(address => FlowInfo) storage _incomingFlows,
        mapping(address => FlowInfo) storage _outgoingFlows
    ) external {
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
    }

    /**
     * @notice Helper for streaming updating
     * @param streaming The streaming being updated
     * @param _streamingId The id of the streaming
     * @param _incomingFlows The incoming flows mapping
     * @param _outgoingFlows The outgoing flows mapping
     * @param _streamings The streamings mapping
     * @param _streamingUpdateRequest The data for the update
     * @return quantityToPayToReceiver
     * @return currentHolding
     * @return expectedHolding
     */
    function updateStreaming(
        Streaming memory streaming,
        uint256 _streamingId,
        mapping(address => FlowInfo) storage _incomingFlows,
        mapping(address => FlowInfo) storage _outgoingFlows,
        mapping(uint256 => Streaming) storage _streamings,
        StreamingUpdateRequest calldata _streamingUpdateRequest
    )
        external
        returns (
            uint256 quantityToPayToReceiver,
            uint256 currentHolding,
            uint256 expectedHolding
        )
    {
        if (block.timestamp > streaming.startingDate) {
            uint256 intervalTranscursed = block.timestamp - streaming.startingDate;
            quantityToPayToReceiver = ((streaming.amountPerSecond * intervalTranscursed));
            streaming.startingDate = uint64(block.timestamp);
        }

        // calculate how much should streaming manager hold now and update
        currentHolding =
            (streaming.amountPerSecond * (streaming.endingDate - streaming.startingDate)) -
            quantityToPayToReceiver;
        expectedHolding =
            _streamingUpdateRequest.amountPerSecond *
            (_streamingUpdateRequest.endingDate - streaming.startingDate);

        // update flow infos
        FlowInfo memory incomingFlowInfo = _incomingFlows[streaming.receiverAddress];
        FlowInfo memory outgoingFlowInfo = _outgoingFlows[streaming.senderAddress];

        _incomingFlows[streaming.receiverAddress].totalPreviousValueGenerated +=
            (block.timestamp - incomingFlowInfo.flow.startingDate) *
            incomingFlowInfo.flow.amountPerSecond;

        _incomingFlows[streaming.receiverAddress].flow.startingDate = uint64(block.timestamp);

        _outgoingFlows[streaming.senderAddress].totalPreviousValueGenerated +=
            (block.timestamp - outgoingFlowInfo.flow.startingDate) *
            outgoingFlowInfo.flow.amountPerSecond;

        _outgoingFlows[streaming.senderAddress].flow.startingDate = uint64(block.timestamp);

        if (quantityToPayToReceiver > 0) {
            _incomingFlows[streaming.receiverAddress].totalPreviousValueTransfered += quantityToPayToReceiver;
            _outgoingFlows[streaming.senderAddress].totalPreviousValueTransfered += quantityToPayToReceiver;
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
        _streamings[_streamingId].startingDate = uint64(block.timestamp);
        _streamings[_streamingId].amountPerSecond = _streamingUpdateRequest.amountPerSecond;
        _streamings[_streamingId].endingDate = _streamingUpdateRequest.endingDate;
    }

    /**
     * @notice Helper for streaming stopping
     * @param streaming The streaming being stopped
     * @param _streamingId The id of the streaming
     * @param _incomingFlows The incoming flows mapping
     * @param _outgoingFlows The outgoing flows mapping
     * @param _streamings The streamings mapping
     * @param _openStreamings The open streamings mapping
     * @return quantityToPay
     * @return quantityToReturn
     */

    function stopStreaming(
        Streaming memory streaming,
        uint256 _streamingId,
        mapping(address => FlowInfo) storage _incomingFlows,
        mapping(address => FlowInfo) storage _outgoingFlows,
        mapping(uint256 => Streaming) storage _streamings,
        mapping(address => mapping(address => bool)) storage _openStreamings
    ) external returns (uint256 quantityToPay, uint256 quantityToReturn) {
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

        // update flow infos
        FlowInfo memory incomingFlowInfo = _incomingFlows[streaming.receiverAddress];
        FlowInfo memory outgoingFlowInfo = _outgoingFlows[streaming.senderAddress];

        _incomingFlows[streaming.receiverAddress].totalPreviousValueGenerated +=
            (block.timestamp - incomingFlowInfo.flow.startingDate) *
            incomingFlowInfo.flow.amountPerSecond;

        _incomingFlows[streaming.receiverAddress].flow.startingDate = uint64(block.timestamp);

        _outgoingFlows[streaming.senderAddress].totalPreviousValueGenerated +=
            (block.timestamp - outgoingFlowInfo.flow.startingDate) *
            outgoingFlowInfo.flow.amountPerSecond;

        _outgoingFlows[streaming.senderAddress].flow.startingDate = uint64(block.timestamp);

        // update flows
        _incomingFlows[streaming.receiverAddress].flow.amountPerSecond -= streaming.amountPerSecond;
        _outgoingFlows[streaming.senderAddress].flow.amountPerSecond -= streaming.amountPerSecond;

        if (quantityToPay > 0) {
            _incomingFlows[streaming.receiverAddress].totalPreviousValueTransfered += quantityToPay;
            _outgoingFlows[streaming.senderAddress].totalPreviousValueTransfered += quantityToPay;
        }
    }

    function getNotYetPaidFlowsValue(
        address account,
        mapping(address => FlowInfo) storage _incomingFlows,
        mapping(address => FlowInfo) storage _outgoingFlows
    ) external view returns (uint256 notYetPaidIncomingFlow, uint256 notYetPaidOutgoingFlow) {
        notYetPaidIncomingFlow =
            _incomingFlows[account].totalPreviousValueGenerated -
            _incomingFlows[account].totalPreviousValueTransfered;
        notYetPaidIncomingFlow +=
            (block.timestamp - _incomingFlows[account].flow.startingDate) *
            _incomingFlows[account].flow.amountPerSecond;
        notYetPaidOutgoingFlow =
            _outgoingFlows[account].totalPreviousValueGenerated -
            _outgoingFlows[account].totalPreviousValueTransfered;
        notYetPaidOutgoingFlow +=
            (block.timestamp - _outgoingFlows[account].flow.startingDate) *
            _outgoingFlows[account].flow.amountPerSecond;
    }
}
