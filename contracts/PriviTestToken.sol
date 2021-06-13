// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ERC20Streamable.sol";

contract PriviTestToken is
    ERC20_,
    ERC20Burnable,
    ERC20Streamable,
    Pausable,
    Ownable
{
    constructor(uint256 initialSupply) ERC20("PriviTestToken", "PTT") {
        // default decimals: 18
        _mint(msg.sender, initialSupply * 10**decimals());
    }

    // Only owner can pause or unpause transfering
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // allow to increment the totalSupply by minting
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function name()
        public
        view
        override(ERC20, ERC20_)
        returns (string memory)
    {
        return ERC20.name();
    }

    function symbol()
        public
        view
        override(ERC20, ERC20_)
        returns (string memory)
    {
        return ERC20.symbol();
    }

    function decimals() public pure override(ERC20, ERC20_) returns (uint8) {
        return 18;
    }

    function totalSupply()
        public
        view
        override(ERC20, ERC20_)
        returns (uint256)
    {
        return ERC20.totalSupply();
    }

    function balanceOf(address account)
        public
        view
        override(ERC20, ERC20_, ERC20Streamable)
        returns (uint256)
    {
        return ERC20Streamable.balanceOf(account);
    }

    function transfer(address recipient, uint256 amount)
        public
        override(ERC20, ERC20_)
        returns (bool)
    {
        return ERC20.transfer(recipient, amount);
    }

    function allowance(address owner, address spender)
        public
        view
        override(ERC20, ERC20_)
        returns (uint256)
    {
        return ERC20.allowance(owner, spender);
    }

    function approve(address spender, uint256 amount)
        public
        override(ERC20, ERC20_)
        returns (bool)
    {
        return ERC20.approve(spender, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override(ERC20, ERC20_) returns (bool) {
        return ERC20.transferFrom(sender, recipient, amount);
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        override(ERC20, ERC20_)
        returns (bool)
    {
        return ERC20.increaseAllowance(spender, addedValue);
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        override(ERC20, ERC20_)
        returns (bool)
    {
        return ERC20.decreaseAllowance(spender, subtractedValue);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override(ERC20, ERC20_) {
        ERC20._transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount)
        internal
        override(ERC20, ERC20_)
    {
        ERC20._mint(account, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override(ERC20, ERC20_)
    {
        ERC20._burn(account, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal override(ERC20, ERC20_) {
        ERC20._approve(owner, spender, amount);
    }

    // Implementing the pausing mechanism through this hook
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20Streamable, ERC20, ERC20_) whenNotPaused {
        ERC20Streamable._beforeTokenTransfer(from, to, amount);
    }
}
