// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract SVTLotteryToken is ERC20, Ownable, ERC20Permit {
    constructor()
        ERC20("SVTLotteryToken", "SLT")
        Ownable(msg.sender)
        ERC20Permit("SVTLotteryToken")
    {
        _mint(msg.sender, 1000000 * 10**18);
    }
}