// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./ERC20.sol";

abstract contract ERC20Streamable is ERC20_ {
    /*
     * Notes:
     * - `id` using senderAddress and receiverAddress as id.
     * - `token` the token info is on the state variables _name and _symbol.
     * - `type` using stype because type is a reserved word.
     */
    struct Streaming {
        bytes32 stype;
        address senderAddress;
        address receiverAddress;
        uint256 amount;
        uint64 frequency;
        uint64 startingDate;
        uint64 endingDate;
    }

    event StreamingCreated(address from, address to);

    /*
     * Hold the streaming by related address (sender or receiver)
     *
     * Notes:
     * - Having to variables to populate is expensive, but this is done on purpose
     * - because this way you can limit the contracts that you can have open
     * - at the same time (the for loop to update balance could be too expensive
     * - and run our of gas if the app is not designed carefully)
     */
    mapping(address => Streaming[]) private _streamingsFromSender;
    mapping(address => Streaming[]) private _streamingsToReceiver;

    modifier hasStreamsOpenToAddress(
        uint256 _expectedCount,
        address _receiverAddress
    ) {
        // Use storage for less gas in readonly
        Streaming[] storage senderStreamings =
            _streamingsFromSender[msg.sender];
        uint256 count = 0;
        for (uint256 i = 0; i < senderStreamings.length; i++) {
            if (senderStreamings[i].receiverAddress == _receiverAddress) {
                count++;
            }
        }
        require(_expectedCount == count, "The expected count doesn't match'");
        _;
    }

    modifier validStreaming(Streaming memory _streaming) {
        require(
            keccak256(abi.encodePacked((_streaming.stype))) ==
                keccak256(abi.encodePacked(("classic"))),
            "Invalid type for the Streaming"
        );
        require(
            _streaming.receiverAddress != address(0),
            "Receiver address couldn't be the 0x0"
        );
        require(_streaming.amount > 0, "Amount should be greater than 1");
        require(_streaming.frequency > 0, "Frequency should be greater than 1");
        require(
            _streaming.startingDate < _streaming.endingDate,
            "The starting date should be before the ending date"
        );
        _;
    }

    /*
     * Creates one streaming
     *
     * Notes:
     * - The sender can't create 2 streaming for the same receiver,
     * - in case this is needed he should update the existing one
     */
    function createStreaming(Streaming memory _streaming)
        external
        virtual
        hasStreamsOpenToAddress(0, _streaming.receiverAddress)
        validStreaming(_streaming)
    {
        require(
            _streaming.senderAddress == msg.sender,
            "The senderAddress should match the transaction sender"
        );
        // Only 5 streams open at the same time for a specific sender (to avoid out of gas in later transfers)
        require(
            _streamingsFromSender[_streaming.senderAddress].length <= 5,
            "Only 5 streams open at the same time"
        );

        Streaming memory stream =
            Streaming({
                stype: _streaming.stype,
                senderAddress: _streaming.senderAddress,
                receiverAddress: _streaming.receiverAddress,
                frequency: uint64(_streaming.frequency),
                amount: _streaming.amount,
                startingDate: uint64(_streaming.startingDate),
                endingDate: uint64(_streaming.endingDate)
            });

        // Save the new stream in the two variables (in order to cheaper checks later)
        _streamingsFromSender[_streaming.senderAddress].push(stream);

        // ! Here there are a vulneribility
        // A DoS attack can be done over one address creating a lot of streams
        // from different address, making the transfer operation, which recalculates
        // the balance over this array always fail with out of gas.
        // This could be avoided by asking the receiver to confirm the flow in a
        // intermediate state of the contract
        _streamingsToReceiver[_streaming.receiverAddress].push(stream);

        emit StreamingCreated(
            _streaming.senderAddress,
            _streaming.receiverAddress
        );
    }

    function updateStreaming(Streaming memory _streaming)
        public
        virtual
        hasStreamsOpenToAddress(1, _streaming.receiverAddress)
        validStreaming(_streaming)
    {
        // update the balances (pay what you owe)
        updateBalanceWithStreamings(_streaming.receiverAddress);

        // make the update
        _updateStreaming(_streaming);
    }

    function stopStreaming(Streaming memory _streaming) public virtual {
        require(
            _streaming.senderAddress == msg.sender,
            "The senderAddress should match the transaction sender"
        );
        // update the balance of the receiver (pay what you owe)
        updateBalanceWithStreamings(_streaming.receiverAddress);

        // stop the streaming
        _stopStreaming(msg.sender, _streaming.receiverAddress);
    }

    // overload with just the receiver
    function stopStreaming(address _receiverAddress) external virtual {
        // update the balance of the receiver (pay what you owe)
        updateBalanceWithStreamings(_receiverAddress);

        // stop the streaming
        _stopStreaming(msg.sender, _receiverAddress);
    }

    /*
     * Get the balance reflecting the values from the streamings
     */
    function balanceOf(address _tokenHolder)
        public
        view
        virtual
        override
        returns (uint256)
    {
        uint256 balance = _balances[_tokenHolder];

        // First add the pending incoming shares
        Streaming[] storage receiverStreamings =
            _streamingsToReceiver[_tokenHolder];
        // Subject to DoS attack as commented in the CreateStreaming function
        for (uint256 i = 0; i < receiverStreamings.length; i++) {
            // This must be true always
            assert(
                receiverStreamings[i].startingDate <
                    receiverStreamings[i].endingDate
            );
            if (block.timestamp > receiverStreamings[i].startingDate) {
                // Add the shares according to the frequency and the transcursed time
                uint256 addTillDate =
                    receiverStreamings[i].endingDate < block.timestamp
                        ? receiverStreamings[i].endingDate
                        : block.timestamp;
                uint256 intervalTranscursed =
                    addTillDate - receiverStreamings[i].startingDate;
                balance += ((receiverStreamings[i].amount *
                    intervalTranscursed) / receiverStreamings[i].frequency);
            }
        }

        // Then remove the pending outgoing shares
        Streaming[] storage senderStreamings =
            _streamingsFromSender[_tokenHolder];
        // This loop is limited by 5 streamings
        for (uint256 i = 0; i < senderStreamings.length; i++) {
            // This must be true always
            assert(
                senderStreamings[i].startingDate <
                    senderStreamings[i].endingDate
            );
            if (block.timestamp > senderStreamings[i].startingDate) {
                // Remove the shares according to the frequency and the transcursed time
                uint256 removeTillDate =
                    senderStreamings[i].endingDate < block.timestamp
                        ? senderStreamings[i].endingDate
                        : block.timestamp;
                uint256 intervalTranscursed =
                    removeTillDate - senderStreamings[i].startingDate;
                balance -= ((senderStreamings[i].amount * intervalTranscursed) /
                    senderStreamings[i].frequency);
            }
        }

        return balance;
    }

    /*
     * Update the balance reflecting the values from the streamings (expensive function)
     *
     * Notes:
     * - Same idea as the balanceOf but modifying the storage, the DRY principle
     * - seems to be broken here, but the logic should be repeated in order
     * - to save gas in balanceOf calls
     */
    function updateBalanceWithStreamings(address _tokenHolder)
        internal
        virtual
    {
        Streaming[] storage receiverStreamings =
            _streamingsToReceiver[_tokenHolder];
        for (uint256 i = 0; i < receiverStreamings.length; i++) {
            // this must be true always
            assert(
                receiverStreamings[i].startingDate <
                    receiverStreamings[i].endingDate
            );
            if (block.timestamp > receiverStreamings[i].startingDate) {
                uint256 addTillDate =
                    receiverStreamings[i].endingDate < block.timestamp
                        ? receiverStreamings[i].endingDate
                        : block.timestamp;
                uint256 intervalTranscursed =
                    addTillDate - receiverStreamings[i].startingDate;

                uint256 quantityChanged =
                    ((receiverStreamings[i].amount * intervalTranscursed) /
                        receiverStreamings[i].frequency);

                // update the balances (expensive operation)
                _balances[_tokenHolder] += quantityChanged;
                _balances[
                    receiverStreamings[i].senderAddress
                ] -= quantityChanged;

                // update stream
                if (addTillDate >= receiverStreamings[i].endingDate) {
                    // remove the stream because is already finished
                    _stopStreaming(
                        _tokenHolder,
                        receiverStreamings[i].senderAddress
                    );
                } else {
                    _updateStreaming(
                        Streaming({
                            stype: receiverStreamings[i].stype,
                            senderAddress: receiverStreamings[i].senderAddress,
                            receiverAddress: receiverStreamings[i]
                                .receiverAddress,
                            frequency: receiverStreamings[i].frequency,
                            amount: receiverStreamings[i].amount,
                            startingDate: uint64(addTillDate),
                            endingDate: receiverStreamings[i].endingDate
                        })
                    );
                }
            }
        }

        Streaming[] storage senderStreamings =
            _streamingsFromSender[_tokenHolder];
        for (uint256 i = 0; i < senderStreamings.length; i++) {
            // this must be true always
            assert(
                senderStreamings[i].startingDate <
                    senderStreamings[i].endingDate
            );
            if (block.timestamp > senderStreamings[i].startingDate) {
                uint256 removeTillDate =
                    senderStreamings[i].endingDate < block.timestamp
                        ? senderStreamings[i].endingDate
                        : block.timestamp;
                uint256 intervalTranscursed =
                    removeTillDate - senderStreamings[i].startingDate;

                uint256 quantityChanged =
                    ((senderStreamings[i].amount * intervalTranscursed) /
                        senderStreamings[i].frequency);

                // update the balances (expensive operation)
                _balances[_tokenHolder] -= quantityChanged;
                _balances[
                    senderStreamings[i].receiverAddress
                ] += quantityChanged;

                // update stream
                if (removeTillDate >= senderStreamings[i].endingDate) {
                    // remove the stream because is already finished
                    _stopStreaming(
                        _tokenHolder,
                        senderStreamings[i].senderAddress
                    );
                } else {
                    _updateStreaming(
                        Streaming({
                            stype: senderStreamings[i].stype,
                            senderAddress: senderStreamings[i].senderAddress,
                            receiverAddress: senderStreamings[i]
                                .receiverAddress,
                            frequency: senderStreamings[i].frequency,
                            amount: senderStreamings[i].amount,
                            startingDate: uint64(removeTillDate),
                            endingDate: senderStreamings[i].endingDate
                        })
                    );
                }
            }
        }
    }

    function _updateStreaming(Streaming memory _streaming) internal {
        // Update the Streaming from both variables (more gas in storage but less in consulting)

        // Use storage for less gas in readonly
        Streaming[] storage senderStreamings =
            _streamingsFromSender[_streaming.senderAddress];
        for (uint256 i = 0; i < senderStreamings.length; i++) {
            if (
                senderStreamings[i].receiverAddress ==
                _streaming.receiverAddress
            ) {
                senderStreamings[i].stype = _streaming.stype;
                senderStreamings[i].amount = _streaming.amount;
                senderStreamings[i].frequency = uint64(_streaming.frequency);
                senderStreamings[i].startingDate = uint64(
                    _streaming.startingDate
                );
                senderStreamings[i].endingDate = uint64(_streaming.endingDate);
                break;
            }
        }

        Streaming[] storage receiverStreamings =
            _streamingsToReceiver[_streaming.receiverAddress];
        for (uint256 i = 0; i < receiverStreamings.length; i++) {
            if (
                receiverStreamings[i].senderAddress == _streaming.senderAddress
            ) {
                receiverStreamings[i].stype = _streaming.stype;
                receiverStreamings[i].amount = _streaming.amount;
                receiverStreamings[i].frequency = uint64(_streaming.frequency);
                receiverStreamings[i].startingDate = uint64(
                    _streaming.startingDate
                );
                receiverStreamings[i].endingDate = uint64(
                    _streaming.endingDate
                );
                break;
            }
        }
    }

    function _stopStreaming(address _fromAddress, address _toAddress) internal {
        // Delete the Streaming from both variables (more gas in storage but less in consulting)

        // Use storage for less gas in readonly
        Streaming[] storage senderStreamings =
            _streamingsFromSender[_fromAddress];
        for (uint256 i = 0; i < senderStreamings.length; i++) {
            if (senderStreamings[i].receiverAddress == _toAddress) {
                // Remove by moving last element to position (order doesn't matter)
                if (i != senderStreamings.length - 1) {
                    senderStreamings[i] = senderStreamings[
                        senderStreamings.length - 1
                    ];
                }
                senderStreamings.pop();
                break;
            }
        }

        Streaming[] storage receiverStreamings =
            _streamingsToReceiver[_toAddress];
        for (uint256 i = 0; i < receiverStreamings.length; i++) {
            if (receiverStreamings[i].senderAddress == _fromAddress) {
                // Remove by moving last element to position (order doesn't matter)
                if (i != receiverStreamings.length - 1) {
                    receiverStreamings[i] = receiverStreamings[
                        receiverStreamings.length - 1
                    ];
                }
                receiverStreamings.pop();
                break;
            }
        }
    }

    // adding the streaming shares calculation through this hook
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        // Update the balance before sending
        updateBalanceWithStreamings(from);
        super._beforeTokenTransfer(from, to, amount);
    }
}
