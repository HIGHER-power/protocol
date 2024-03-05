// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "../HIGHERToken.sol";

contract HIGHERTokenTesting is HIGHERToken {
    constructor(
        string memory name,
        string memory symbol
    ) HIGHERToken(name, symbol) {}

    function rebase(uint256 newCurrentSupply) external {
        require(newCurrentSupply > 0, "cannot have 0 supply");
        emit Rebased(currentSupply, newCurrentSupply);
        currentSupply = newCurrentSupply;
    }
}
