// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./StreamingLibrary.sol";
import "./StreamingManager.sol";
import "./Structs.sol";

/**
 * @title Streaming extension for an ERC20 token
 * @author Eric Nordelo
 **/
abstract contract ERC20Streamable is ERC20, AccessControl {
    using Counters for Counters.Counter;
    using StreamingLibrary for Streaming;

    Counters.Counter private _streamingIds;

    bytes32 public constant ADMIN = keccak256("admin");

    address public streamingManagerAddress;

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

    /**
     * @notice Allows admins to set the Streaming Manager contract address
     * @param _streamingManagerAddress The address of the contract
     **/
    function setStreamingManagerAddress(address _streamingManagerAddress) external onlyRole(ADMIN) {
        streamingManagerAddress = _streamingManagerAddress;
    }

    modifier isValidStreaming(Streaming memory _streaming) {
        require(
            keccak256(abi.encodePacked((_streaming.stype))) == keccak256(abi.encodePacked(("classic"))),
            "Invalid type"
        );
        require(_streaming.senderAddress == msg.sender, "Invalid sender");
        require(_streaming.receiverAddress != address(0), "Invalid receiver");
        require(_streaming.amountPerSecond > 0, "Invalid amount per second");
        _;
    }

    /**
     * @notice Create a streaming between to addresses
     * @param _streaming The data of the streaming
     * @return newStreamingId The id of the new streaming
     **/
    function createStreaming(Streaming memory _streaming)
        public
        isValidStreaming(_streaming)
        returns (uint256 newStreamingId)
    {
        require(block.timestamp < _streaming.endingDate, "Invalid ending date");
        require(!_openStreamings[_streaming.senderAddress][_streaming.receiverAddress], "Existing streaming");
        _streaming.startingDate = uint64(block.timestamp);

        uint256 totalAmount = _streaming.amountPerSecond * (_streaming.endingDate - _streaming.startingDate);

        // should have enough balance to open the streaming
        require(totalAmount <= balanceOf(msg.sender), "Not enough balance");

        _streamingIds.increment();
        newStreamingId = _streamingIds.current();

        _streamings[newStreamingId] = _streaming;
        _openStreamings[_streaming.senderAddress][_streaming.receiverAddress] = true;

        // use the library to create streaming
        _streaming.createStreaming(_incomingFlows, _outgoingFlows);

        // transfer the total amount to the manager
        transfer(streamingManagerAddress, totalAmount);
        StreamingManager(streamingManagerAddress).incrementHoldingBalance(
            _streaming.senderAddress,
            totalAmount
        );

        emit StreamingCreated(
            _streaming.senderAddress,
            _streaming.receiverAddress,
            newStreamingId,
            _streaming.endingDate
        );
    }

    /**
     * @notice Update a streaming between to addresses
     * @param _streamingId The id of the streaming to update
     * @param _streamingUpdateRequest The data of the streaming update
     */
    function updateStreaming(uint256 _streamingId, StreamingUpdateRequest calldata _streamingUpdateRequest)
        external
    {
        Streaming memory streaming = getStreaming(_streamingId);

        if (
            streaming.startingDate >= _streamingUpdateRequest.endingDate ||
            _streamingUpdateRequest.endingDate <= block.timestamp ||
            streaming.senderAddress != msg.sender ||
            _streamingUpdateRequest.amountPerSecond <= 0
        ) {
            revert("Invalid request");
        }

        if (streaming.endingDate <= block.timestamp) {
            _stop(streaming, _streamingId);
        } else {
            (uint256 quantityToPayToReceiver, uint256 currentHolding, uint256 expectedHolding) = streaming
            .updateStreaming(
                _streamingId,
                _incomingFlows,
                _outgoingFlows,
                _streamings,
                _streamingUpdateRequest
            );

            // make the transfers (the payment and the return)
            if (quantityToPayToReceiver > 0) {
                StreamingManager(streamingManagerAddress).transferAndUpdateHoldingBalance(
                    streaming.senderAddress,
                    streaming.receiverAddress,
                    quantityToPayToReceiver
                );
            }
            // update streaming manager balance
            if (currentHolding > expectedHolding) {
                StreamingManager(streamingManagerAddress).transferAndUpdateHoldingBalance(
                    streaming.senderAddress,
                    streaming.senderAddress,
                    currentHolding - expectedHolding
                );
            } else if (currentHolding < expectedHolding) {
                transfer(streamingManagerAddress, expectedHolding - currentHolding);
                StreamingManager(streamingManagerAddress).incrementHoldingBalance(
                    streaming.senderAddress,
                    expectedHolding - currentHolding
                );
            }

            emit StreamingUpdated(
                streaming.senderAddress,
                streaming.receiverAddress,
                _streamingId,
                _streamingUpdateRequest.endingDate
            );
        }
    }

    /**
     * @notice Stop a streaming between to addresses
     * @dev Protected against reentracy by check-effect-interactions pattern
     * @param _streamingId The id of the streaming to stop
     */
    function stopStreaming(uint256 _streamingId) public {
        Streaming memory streaming = getStreaming(_streamingId);

        // check only sender or admin
        require(streaming.senderAddress == msg.sender || hasRole(ADMIN, msg.sender), "Permission denied");

        _stop(streaming, _streamingId);
    }

    /**
     * @notice Getter for a streaming
     * @param _streamingId The id of the streaming
     * @return streaming The data of the streaming
     */
    function getStreaming(uint256 _streamingId) public view returns (Streaming memory streaming) {
        streaming = _streamings[_streamingId];
        require(streaming.amountPerSecond > 0, "Unexisting streaming");
    }

    /**
     * @notice Returns the balance of an account with the streaming info
     * @param account The address of the account to check
     * @return The current balance with streamings
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        (uint256 notYetPaidIncomingFlow, uint256 notYetPaidOutgoingFlow) = StreamingLibrary
        .getNotYetPaidFlowsValue(account, _incomingFlows, _outgoingFlows);

        // this is the sender balance holded in the streaming manager
        uint256 balanceHolded = StreamingManager(streamingManagerAddress).getHoldingBalance(account);

        return super.balanceOf(account) + notYetPaidIncomingFlow - notYetPaidOutgoingFlow + balanceHolded;
    }

    function _stop(Streaming memory streaming, uint256 _streamingId) internal {
        // update the balance of the receiver (pay what you owe)

        // this must be true always
        assert(streaming.startingDate < streaming.endingDate);

        (uint256 quantityToPay, uint256 quantityToReturn) = streaming.stopStreaming(
            _streamingId,
            _incomingFlows,
            _outgoingFlows,
            _streamings,
            _openStreamings
        );

        // make the transfers (the payment and the return)
        if (quantityToPay > 0) {
            StreamingManager(streamingManagerAddress).transferAndUpdateHoldingBalance(
                streaming.senderAddress,
                streaming.receiverAddress,
                quantityToPay
            );
        }
        if (quantityToReturn > 0) {
            StreamingManager(streamingManagerAddress).transferAndUpdateHoldingBalance(
                streaming.senderAddress,
                streaming.senderAddress,
                quantityToReturn
            );
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
