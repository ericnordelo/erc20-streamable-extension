// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StreamingManager {
    address public immutable erc20StreamableAddress;

    constructor(address _erc20StreamableAddress) {
        erc20StreamableAddress = _erc20StreamableAddress;
    }

    function transfer(address _to, uint256 _amount) external {
        require(msg.sender == erc20StreamableAddress, "Invalid sender");
        ERC20 token = ERC20(erc20StreamableAddress);
        token.transfer(_to, _amount);
    }
}
