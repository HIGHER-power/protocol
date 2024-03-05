// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";
import "./Arithemtic.sol";

library CircularQueue {
    using Arithmetic for uint256;

    uint256 constant QUEUE_SIZE = 10;

    struct Value {
        uint128 price;
        uint128 time;
    }

    struct T {
        Value[QUEUE_SIZE] values;
        uint256 currentIndex;
    }

    function add(T storage self, uint256 price, uint256 time) internal {
        self.values[self.currentIndex] = Value(uint128(price), uint128(time));
        self.currentIndex = (self.currentIndex + 1) % QUEUE_SIZE;
    }

    function getLatest(T storage self) internal view returns (Value memory) {
        uint256 i = self.currentIndex == 0
            ? QUEUE_SIZE - 1
            : self.currentIndex - 1;
        return self.values[i];
    }

    function getClosestTo(
        T storage self,
        uint256 timestamp
    ) internal view returns (Value memory) {
        uint256 minDiff = type(uint256).max;
        uint256 minDiffIndex = 0;
        for (uint256 i = 0; i < QUEUE_SIZE; i++) {
            if (self.values[i].time == 0) break;
            uint256 diff = uint256(self.values[i].time).subAbs(timestamp);
            if (diff < minDiff) {
                minDiff = diff;
                minDiffIndex = i;
            }
        }
        return self.values[minDiffIndex];
    }

    function clear(T storage self) internal {
        for (uint256 i = 0; i < QUEUE_SIZE; i++) {
            delete self.values[i];
        }
        self.currentIndex = 0;
    }
}
