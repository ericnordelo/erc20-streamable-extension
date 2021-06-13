// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library HelperLibrary {
    /*
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

    function balanceOf(
        uint256 storedBalance,
        Streaming[] storage receiverStreamings,
        Streaming[] storage senderStreamings
    ) public view returns (uint256) {
        uint256 balance = storedBalance;

        // First add the pending incoming shares

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
}
