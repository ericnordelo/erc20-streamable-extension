// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

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
        uint256 frequency;
        uint256 amount;
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
        uint256 expectedCount,
        address receiverAddress
    ) {
        Streaming[] storage senderStreamings =
            _streamingsFromSender[msg.sender];
        uint256 count = 0;
        for (uint256 i = 0; i < senderStreamings.length; i++) {
            if (senderStreamings[i].receiverAddress == receiverAddress) {
                count++;
            }
        }
        require(expectedCount == count);
        _;
    }

    function createStreaming(
        string calldata stype,
        address receiverAddress,
        uint256 frequency,
        uint256 amount,
        uint64 startingDate,
        uint64 endingDate
    ) external virtual hasStreamsOpenToAddress(0, receiverAddress) {
        // Only 5 streams open at the same time for a specific sender (to avoid out of gas in later transfers)
        require(
            _streamingsFromSender[msg.sender].length <= 5,
            "Only 5 streams open at the same time"
        );

        Streaming memory stream =
            Streaming({
                stype: stype,
                senderAddress: msg.sender,
                receiverAddress: receiverAddress,
                frequency: frequency,
                amount: amount,
                startingDate: startingDate,
                endingDate: endingDate
            });

        // Save the new stream in the two variables (in order to cheaper checks later)
        _streamingsFromSender[msg.sender].push(stream);

        // ! Here there are a vulneribility
        // A DoS attack can be done over one address creating a lot of flows
        // from different address, making the transfer operation, which recalculates
        // the balance over this array always fail with out of gas.
        // This could be avoided by asking the receiver to confirm the flow in a
        // intermediate state of the contract
        _streamingsToReceiver[receiverAddress].push(stream);

        emit StreamingCreated(msg.sender, receiverAddress);
    }

    function updateStreaming(
        string calldata stype,
        address receiverAddress,
        uint256 frequency,
        uint256 amount,
        uint64 startingDate,
        uint64 endingDate
    ) external virtual {}

    function stopStreaming(address receiverAddress) external virtual {}
}
