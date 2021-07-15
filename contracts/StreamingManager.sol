// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title Streaming manager
 * @author Eric Nordelo
 * @notice Arbitrage between the streaming sender and receivers (manage the payments)
 */
contract StreamingManager {
    address public immutable erc20StreamableAddress;

    mapping(address => uint256) private _holdingBalance;

    constructor(address _erc20StreamableAddress) {
        erc20StreamableAddress = _erc20StreamableAddress;
    }

    function getHoldingBalance(address _account) external view returns (uint256) {
        require(msg.sender == erc20StreamableAddress, "Invalid sender");
        return _holdingBalance[_account];
    }

    function transfer(address _to, uint256 _amount) external {
        require(msg.sender == erc20StreamableAddress, "Invalid sender");
        ERC20 token = ERC20(erc20StreamableAddress);
        token.transfer(_to, _amount);
    }

    function transferAndUpdateHoldingBalance(
        address _from,
        address _to,
        uint256 _amount
    ) external {
        require(msg.sender == erc20StreamableAddress, "Invalid sender");

        _holdingBalance[_from] -= _amount;
        ERC20 token = ERC20(erc20StreamableAddress);
        token.transfer(_to, _amount);
    }

    function incrementHoldingBalance(address _account, uint256 _amount) external {
        require(msg.sender == erc20StreamableAddress, "Invalid sender");
        _holdingBalance[_account] += _amount;
    }
}
