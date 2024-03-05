// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/console.sol";

import {ERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../libraries/Arithemtic.sol";
import "../libraries/UniswapV2OracleLibrary.sol";
import "../libraries/CircularQueue.sol";

import "../interfaces/IHIGHERToken.sol";

import "../integrations/IThrusterRouter02.sol";
import "../integrations/IThrusterFactory.sol";
import "../integrations/IThrusterPair.sol";

contract HIGHERToken is IHIGHERToken, ERC20 {
    using Arithmetic for uint256;
    using CircularQueue for CircularQueue.T;

    uint256 public constant TARGET_PRICE = 0.001e18;
    uint256 public constant MAX_REBASING_FRACTION = 0.04e18;
    uint256 public constant MAX_TWAP_DEVIATION = 1.05e18;
    uint256 public constant REBASING_FREQUENCY = 4 hours;
    uint256 public constant TWAP_WINDOW = 1 hours;
    uint256 public constant TWAP_FREQUENCY = 360;

    IThrusterRouter02 router =
        IThrusterRouter02(0x98994a9A7a2570367554589189dC9772241650f6);
    bool public isToken0;

    address public minter;
    uint256 public lastRebase;

    uint256 internal currentSupply;
    mapping(address => uint256) public tokenShares;
    CircularQueue.T internal pricesQueue;

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        isToken0 = address(this) < router.WETH();
    }

    function getPool() public view returns (IThrusterPair) {
        return
            IThrusterPair(
                IThrusterFactory(router.factory()).getPair(
                    address(this),
                    router.WETH()
                )
            );
    }

    function setMinter(address minter_) external {
        require(minter == address(0), "minter already set");
        minter = minter_;
    }

    function balanceOf(
        address account
    ) public view override(ERC20, IERC20) returns (uint256) {
        return currentSupply.mul(tokenShares[account], 27);
    }

    function _update(
        address from,
        address to,
        uint256 value
    ) internal override {
        if (from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSupply never overflows
            currentSupply += value;
        } else {
            uint256 fromBalance = balanceOf(from);
            if (fromBalance < value) {
                revert ERC20InsufficientBalance(from, fromBalance, value);
            }
            unchecked {
                // Overflow not possible: value <= fromBalance <= totalSupply.
                uint256 share = value.div(currentSupply, 27);
                tokenShares[from] -= share;
            }
        }

        if (to == address(0)) {
            unchecked {
                // Overflow not possible: value <= totalSupply or value <= fromBalance <= totalSupply.
                currentSupply -= value;
            }
        } else {
            unchecked {
                // Overflow not possible: balance + value is at most totalSupply, which we know fits into a uint256.
                uint256 share = value.div(currentSupply, 27);
                tokenShares[to] += share;
            }
        }

        address pool = address(getPool());
        if (pool != address(0)) {
            if (from == pool || to == pool) {
                _storeLatestPrice();
            } else {
                rebase();
            }
        }

        emit Transfer(from, to, value);
    }

    function mint(address account, uint256 amount) external {
        require(msg.sender == minter, "not authorized");
        require(currentSupply == 0, "can only mint once");
        lastRebase = block.timestamp;
        _mint(account, amount);
    }

    function totalSupply()
        public
        view
        override(ERC20, IERC20)
        returns (uint256)
    {
        return currentSupply;
    }

    function rebase() public {
        if (block.timestamp - lastRebase < REBASING_FREQUENCY) return;

        (uint256 higherReserve, uint256 ethReserve) = _getReserves();
        uint256 ethOut = router.getAmountOut(1e18, higherReserve, ethReserve);
        uint256 currentTwap = getCurrentTwapPrice();
        uint256 diff = ethOut > currentTwap
            ? ethOut.div(currentTwap)
            : currentTwap.div(ethOut);

        if (diff > MAX_TWAP_DEVIATION) return;

        _computeAndExecuteSupplyChange(
            uint256(higherReserve),
            uint256(ethReserve)
        );

        getPool().sync();

        pricesQueue.clear();
        _storeLatestPrice();
        lastRebase = block.timestamp;
    }

    function _computeAndExecuteSupplyChange(
        uint256 higherReserve,
        uint256 ethReserve
    ) internal {
        uint256 targetBalance = ethReserve.div(TARGET_PRICE);
        uint256 supplyScale = targetBalance.div(higherReserve);
        if (supplyScale > 1e18 + MAX_REBASING_FRACTION) {
            supplyScale = 1e18 + MAX_REBASING_FRACTION;
        } else if (supplyScale < 1e18 - MAX_REBASING_FRACTION) {
            supplyScale = 1e18 - MAX_REBASING_FRACTION;
        }
        uint256 newCurrentSupply = currentSupply.mul(supplyScale);
        emit Rebased(currentSupply, newCurrentSupply);
        currentSupply = newCurrentSupply;
    }

    function _storeLatestPrice() internal {
        uint256 latestUpdate = pricesQueue.getLatest().time;
        if (block.timestamp - latestUpdate < TWAP_FREQUENCY) return;

        (
            uint256 priceHigherCumulative,
            uint256 blockTimestamp
        ) = _getCurrentCumulativePrices();
        if (blockTimestamp == 0) return;

        pricesQueue.add(priceHigherCumulative, blockTimestamp);
    }

    function getCurrentTwapPrice() public view returns (uint256) {
        (
            uint256 priceHigherCumulative,
            uint256 blockTimestamp
        ) = _getCurrentCumulativePrices();
        if (blockTimestamp == 0) return 0;

        CircularQueue.Value memory pastPrice = pricesQueue.getClosestTo(
            block.timestamp - 3600
        );
        require(blockTimestamp != pastPrice.time, "no twap");
        return
            (priceHigherCumulative - pastPrice.price) /
            (blockTimestamp - pastPrice.time);
    }

    function _getReserves()
        internal
        view
        returns (uint256 higherReserve, uint256 ethReserve)
    {
        if (isToken0) {
            (higherReserve, ethReserve, ) = getPool().getReserves();
        } else {
            (ethReserve, higherReserve, ) = getPool().getReserves();
        }
    }

    function _getCurrentCumulativePrices()
        internal
        view
        returns (uint256 higherPrice, uint256 timestamp)
    {
        address pool = address(getPool());
        if (pool == address(0)) return (0, 0);
        if (isToken0) {
            (higherPrice, , timestamp) = UniswapV2OracleLibrary
                .currentCumulativePrices(pool);
        } else {
            (, higherPrice, timestamp) = UniswapV2OracleLibrary
                .currentCumulativePrices(pool);
        }
    }
}
