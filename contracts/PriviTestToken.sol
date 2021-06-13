// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./ERC20Burnable.sol";
import "./ERC20Streamable.sol";

contract PriviTestToken is ERC20_, ERC20Burnable_, ERC20Streamable, Ownable {
    constructor(uint256 initialSupply) ERC20_("PriviTestToken", "PTT") {
        // default decimals: 9
        _mint(msg.sender, initialSupply * 10**decimals());
    }

    // allow to increment the totalSupply by minting
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    function name() public view override(ERC20_) returns (string memory) {
        return ERC20_.name();
    }

    function symbol() public view override(ERC20_) returns (string memory) {
        return ERC20_.symbol();
    }

    function decimals() public pure override(ERC20_) returns (uint8) {
        return 9;
    }

    function totalSupply() public view override(ERC20_) returns (uint256) {
        return ERC20_.totalSupply();
    }

    function balanceOf(address account)
        public
        view
        override(ERC20_, ERC20Streamable)
        returns (uint256)
    {
        return ERC20Streamable.balanceOf(account);
    }

    function transfer(address recipient, uint256 amount)
        public
        override(ERC20_)
        returns (bool)
    {
        return ERC20_.transfer(recipient, amount);
    }

    function allowance(address owner, address spender)
        public
        view
        override(ERC20_)
        returns (uint256)
    {
        return ERC20_.allowance(owner, spender);
    }

    function approve(address spender, uint256 amount)
        public
        override(ERC20_)
        returns (bool)
    {
        return ERC20_.approve(spender, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override(ERC20_) returns (bool) {
        return ERC20_.transferFrom(sender, recipient, amount);
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        override(ERC20_)
        returns (bool)
    {
        return ERC20_.increaseAllowance(spender, addedValue);
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        override(ERC20_)
        returns (bool)
    {
        return ERC20_.decreaseAllowance(spender, subtractedValue);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override(ERC20_) {
        ERC20_._transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal override(ERC20_) {
        ERC20_._mint(account, amount);
    }

    function _burn(address account, uint256 amount) internal override(ERC20_) {
        ERC20_._burn(account, amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal override(ERC20_) {
        ERC20_._approve(owner, spender, amount);
    }

    // Implementing the pausing mechanism through this hook
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20Streamable, ERC20_) {
        ERC20Streamable._beforeTokenTransfer(from, to, amount);
    }
}
