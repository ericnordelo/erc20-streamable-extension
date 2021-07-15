// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../ERC20Streamable.sol";

contract SocialTokenMock is ERC20, ERC20Streamable, Ownable {
    constructor(
        uint256 initialSupply,
        string memory tokenName,
        string memory tokenSymbol
    ) ERC20(tokenName, tokenSymbol) {
        // default decimals: 18
        _mint(msg.sender, initialSupply * 10**decimals());
    }

    // allow to increment the totalSupply by minting
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function balanceOf(address account) public view override(ERC20, ERC20Streamable) returns (uint256) {
        return ERC20Streamable.balanceOf(account);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal view override(ERC20Streamable, ERC20) {
        ERC20Streamable._beforeTokenTransfer(from, to, amount);
    }
}
