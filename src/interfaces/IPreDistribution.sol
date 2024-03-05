// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

interface IPreDistribution {
    function getHigher() external payable;

    function whiteListClaim() external payable;

    function endPreDistribution() external;

    function claimHigher() external;

    function claimETHBack() external;
}
