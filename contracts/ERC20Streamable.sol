// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "./ERC20.sol";

abstract contract ERC20Streamable is ERC20 {
    /**
     * Notes:
     * - `id` using senderAddress and receiverAddress as id.
     * - `token` the token info is on the state variables _name and _symbol.
     * - `type` using stype because type is a reserved word.
     */
    struct Streaming {
        string stype;
        address senderAddress;
        address receiverAddress;
        uint256 amount;
        uint64 frequency;
        uint64 startingDate;
        uint64 endingDate;
    }

    event StreamingCreated(address from, address to);

    /**
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
        require(_expectedCount == count);
        _;
    }

    modifier validStreaming(
        string memory _stype,
        address _receiverAddress,
        uint256 _amount,
        uint256 _frequency,
        uint256 _startingDate,
        uint256 _endingDate
    ) {
        require(
            keccak256(abi.encodePacked((_stype))) ==
                keccak256(abi.encodePacked(("classic")))
        );
        require(_receiverAddress != address(0));
        require(_amount > 0);
        require(_frequency > 0);
        require(_startingDate < _endingDate);
        _;
    }

    /**
     * Creates one streaming
     *
     * Notes:
     * - The sender can't create 2 streaming for the same receiver,
     * - in case this is needed he should update the existing one
     */
    function createStreaming(
        string calldata _stype,
        address _receiverAddress,
        uint256 _amount,
        uint256 _frequency,
        uint256 _startingDate,
        uint256 _endingDate
    )
        external
        virtual
        hasStreamsOpenToAddress(0, _receiverAddress)
        validStreaming(
            _stype,
            _receiverAddress,
            _amount,
            _frequency,
            _startingDate,
            _endingDate
        )
    {
        // Only 5 streams open at the same time for a specific sender (to avoid out of gas in later transfers)
        require(
            _streamingsFromSender[msg.sender].length <= 5,
            "Only 5 streams open at the same time"
        );

        Streaming memory stream =
            Streaming({
                stype: _stype,
                senderAddress: msg.sender,
                receiverAddress: _receiverAddress,
                frequency: uint64(_frequency),
                amount: _amount,
                startingDate: uint64(_startingDate),
                endingDate: uint64(_endingDate)
            });

        // Save the new stream in the two variables (in order to cheaper checks later)
        _streamingsFromSender[msg.sender].push(stream);

        // ! Here there are a vulneribility
        // A DoS attack can be done over one address creating a lot of streams
        // from different address, making the transfer operation, which recalculates
        // the balance over this array always fail with out of gas.
        // This could be avoided by asking the receiver to confirm the flow in a
        // intermediate state of the contract
        _streamingsToReceiver[_receiverAddress].push(stream);

        emit StreamingCreated(msg.sender, _receiverAddress);
    }

    function updateStreaming(
        string calldata _stype,
        address _receiverAddress,
        uint256 _amount,
        uint256 _frequency,
        uint256 _startingDate,
        uint256 _endingDate
    )
        external
        virtual
        hasStreamsOpenToAddress(1, _receiverAddress)
        validStreaming(
            _stype,
            _receiverAddress,
            _amount,
            _frequency,
            _startingDate,
            _endingDate
        )
    {
        // update the balances (pay what you owe)
        updateBalanceWithStreamings(_receiverAddress);

        // make the update
        _updateStreaming(
            _stype,
            msg.sender,
            _receiverAddress,
            _amount,
            _frequency,
            _startingDate,
            _endingDate
        );
    }

    function stopStreaming(address _receiverAddress) external virtual {
        // update the balance of the receiver (pay what you owe)
        updateBalanceWithStreamings(_receiverAddress);

        // stop the streaming
        _stopStreaming(msg.sender, _receiverAddress);
    }

    /**
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

    /**
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
                        receiverStreamings[i].stype,
                        receiverStreamings[i].senderAddress,
                        receiverStreamings[i].receiverAddress,
                        receiverStreamings[i].amount,
                        receiverStreamings[i].frequency,
                        addTillDate,
                        receiverStreamings[i].endingDate
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
                        senderStreamings[i].stype,
                        senderStreamings[i].senderAddress,
                        senderStreamings[i].receiverAddress,
                        senderStreamings[i].amount,
                        senderStreamings[i].frequency,
                        removeTillDate,
                        senderStreamings[i].endingDate
                    );
                }
            }
        }
    }

    function _updateStreaming(
        string memory _stype,
        address _senderAddress,
        address _receiverAddress,
        uint256 _amount,
        uint256 _frequency,
        uint256 _startingDate,
        uint256 _endingDate
    ) internal {
        // Update the Streaming from both variables (more gas in storage but less in consulting)

        // Use storage for less gas in readonly
        Streaming[] storage senderStreamings =
            _streamingsFromSender[_senderAddress];
        for (uint256 i = 0; i < senderStreamings.length; i++) {
            if (senderStreamings[i].receiverAddress == _receiverAddress) {
                senderStreamings[i].stype = _stype;
                senderStreamings[i].amount = _amount;
                senderStreamings[i].frequency = uint64(_frequency);
                senderStreamings[i].startingDate = uint64(_startingDate);
                senderStreamings[i].endingDate = uint64(_endingDate);
                break;
            }
        }

        Streaming[] storage receiverStreamings =
            _streamingsToReceiver[_receiverAddress];
        for (uint256 i = 0; i < receiverStreamings.length; i++) {
            if (receiverStreamings[i].senderAddress == _senderAddress) {
                receiverStreamings[i].stype = _stype;
                receiverStreamings[i].amount = _amount;
                receiverStreamings[i].frequency = uint64(_frequency);
                receiverStreamings[i].startingDate = uint64(_startingDate);
                receiverStreamings[i].endingDate = uint64(_endingDate);
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
    ) internal override {
        // Update the balance before sending
        updateBalanceWithStreamings(from);
        super._beforeTokenTransfer(from, to, amount);
    }
}
