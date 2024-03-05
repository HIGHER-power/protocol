// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

interface IHIGHERToken is IERC20 {
    event Rebased(uint256 previousSupply, uint256 newSupply);

    function setMinter(address minter_) external;

    function mint(address to, uint256 amount) external;
}
