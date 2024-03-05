// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

library Arithmetic {
    uint8 internal constant DECIMALS = 18;

    function div(
        uint256 value,
        uint256 divisor
    ) internal pure returns (uint256) {
        return div(value, divisor, DECIMALS);
    }

    function div(
        uint256 value,
        uint256 divisor,
        uint8 decimals
    ) internal pure returns (uint256) {
        return (value * 10 ** decimals) / divisor;
    }

    function mul(
        uint256 value,
        uint256 multiplier
    ) internal pure returns (uint256) {
        return mul(value, multiplier, DECIMALS);
    }

    function mul(
        uint256 value,
        uint256 multiplier,
        uint8 decimals
    ) internal pure returns (uint256) {
        return (value * multiplier) / 10 ** decimals;
    }

    function subAbs(
        uint256 value,
        uint256 subtrahend
    ) internal pure returns (uint256) {
        return value > subtrahend ? value - subtrahend : subtrahend - value;
    }
}
