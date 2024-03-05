// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import "../libraries/Arithemtic.sol";
import "../interfaces/IHIGHERToken.sol";
import "../interfaces/IPreDistribution.sol";
import "../libraries/Arithemtic.sol";
import "../integrations/IThrusterRouter02.sol";

import "forge-std/console.sol";

contract PreDistribution is IPreDistribution {
    using Arithmetic for uint256;
    using Address for address payable;

    event HigherClaimed(address indexed user, uint256 amount);
    event ETHClaimedBack(address indexed user, uint256 amount);

    uint256 public constant PRE_DISTRIBUTION_TIME = 24 hours;
    uint256 public constant MIN_PRE_DISTRIBUTION_AMOUNT = 20e18;
    uint256 public constant PREMIUM_PRICE = 0.000125e18;
    uint256 public constant WHITELIST_PRICE = 0.00025e18;
    IThrusterRouter02 public constant ROUTER =
        IThrusterRouter02(0x98994a9A7a2570367554589189dC9772241650f6);
    uint256 public constant TRANCH_SIZE = 5_000e18;
    uint256 public constant TARGET_PRICE = 0.001e18;
    uint256 public constant DISCOUNT_FACTOR = 0.984e18;
    uint256 public constant PRE_DISTRIBUTION_START_TIME = 1709672400; // 2024-03-05 21:00:00 UTC

    mapping(address => uint256) public premiumWhitelist;
    mapping(address => uint256) public whitelist;

    mapping(address => uint256) public higherTokenBalance;
    mapping(address => uint256) public ethDeposited;

    IHIGHERToken public higherToken;
    uint256 public totalEthDeposited;
    uint256 public higherSold;
    uint256 public leftInTranch;
    uint256 public currentDiscount;

    address public deployer;

    bool public preDistributionSucceeded;
    uint256 public immutable preDistributionEndTime;
    bool public preDistributionEnded;
    uint256 public finalSupply;

    constructor(
        address higherToken_,
        address[] memory premiumWhitelistAddresses,
        address[] memory whitelistAddresses
    ) {
        deployer = msg.sender;
        higherToken = IHIGHERToken(higherToken_);
        higherToken.setMinter(address(this));
        currentDiscount = 0.75e18;
        leftInTranch = TRANCH_SIZE;
        preDistributionEndTime =
            PRE_DISTRIBUTION_START_TIME +
            PRE_DISTRIBUTION_TIME;

        for (uint256 i = 0; i < premiumWhitelistAddresses.length; i++) {
            premiumWhitelist[premiumWhitelistAddresses[i]] = 0.5e18;
        }

        for (uint256 i = 0; i < whitelistAddresses.length; i++) {
            whitelist[whitelistAddresses[i]] = 0.15e18;
        }
    }

    function getHigher() external payable {
        require(
            block.timestamp >= PRE_DISTRIBUTION_START_TIME,
            "pre-distribution has not started"
        );
        require(
            preDistributionEndTime > block.timestamp,
            "pre-distribution has ended"
        );

        uint256 ethRemaining = msg.value;
        uint256 currentPrice;
        uint256 higherToDistribute;

        totalEthDeposited += msg.value;
        ethDeposited[msg.sender] += msg.value;

        while (ethRemaining > 0) {
            currentPrice = TARGET_PRICE.mul(1e18 - currentDiscount);
            uint256 requiredHigher = ethRemaining.div(currentPrice);
            if (leftInTranch > requiredHigher) {
                higherToDistribute += requiredHigher;
                ethRemaining = 0;
                leftInTranch -= requiredHigher;
            } else {
                uint256 ethRequired = leftInTranch.mul(currentPrice);
                higherToDistribute += leftInTranch;
                ethRemaining -= ethRequired;
                leftInTranch = TRANCH_SIZE;
                currentDiscount = currentDiscount.mul(DISCOUNT_FACTOR);
            }
        }
        higherSold += higherToDistribute;
        higherTokenBalance[msg.sender] += higherToDistribute;
    }

    function whiteListClaim() external payable {
        require(
            block.timestamp >= PRE_DISTRIBUTION_START_TIME,
            "pre-distribution has not started"
        );
        require(
            preDistributionEndTime > block.timestamp,
            "pre-distribution has ended"
        );

        uint256 ethSent = msg.value;
        uint256 price;

        totalEthDeposited += msg.value;
        ethDeposited[msg.sender] += msg.value;

        if (premiumWhitelist[msg.sender] > 0) {
            price = PREMIUM_PRICE;
            premiumWhitelist[msg.sender] -= ethSent;
        } else if (whitelist[msg.sender] > 0) {
            price = WHITELIST_PRICE;
            whitelist[msg.sender] -= ethSent;
        } else {
            revert("not in the whitelist");
        }
        uint256 higherToDistribute = ethSent.div(price);
        higherSold += higherToDistribute;
        higherTokenBalance[msg.sender] += higherToDistribute;
    }

    function endPreDistribution() external {
        require(
            block.timestamp > preDistributionEndTime,
            "pre-distribution has not ended"
        );
        require(!preDistributionEnded, "pre-distribution has been ended");

        uint256 totalEth = address(this).balance;
        if (totalEth < MIN_PRE_DISTRIBUTION_AMOUNT) {
            preDistributionEnded = true;
            preDistributionSucceeded = false;
            return;
        }
        uint256 currentPrice = TARGET_PRICE.mul(1e18 - currentDiscount);
        uint256 higherToMint = totalEth.div(currentPrice);
        finalSupply = higherToMint + higherSold;

        higherToken.mint(address(this), finalSupply);
        higherToken.approve(address(ROUTER), higherToMint);
        ROUTER.addLiquidityETH{value: totalEth}(
            address(higherToken),
            higherToMint,
            0,
            0,
            address(0),
            block.timestamp
        );
        preDistributionEnded = true;
        preDistributionSucceeded = true;
    }

    function claimHigher() external {
        require(preDistributionEnded, "pre-distribution still ongoing");
        require(
            preDistributionSucceeded,
            "pre-distribution did not succeed, claim back ETH instead"
        );

        uint256 share = higherTokenBalance[msg.sender].div(finalSupply);
        uint256 toTransfer = share.mul(higherToken.totalSupply());
        higherTokenBalance[msg.sender] = 0;

        higherToken.transfer(msg.sender, toTransfer);

        emit HigherClaimed(msg.sender, toTransfer);
    }

    function claimETHBack() external {
        require(preDistributionEnded, "pre-distribution still ongoing");
        require(
            !preDistributionSucceeded,
            "pre-distribution succeeded, claim Higher instead"
        );

        uint256 toRefund = ethDeposited[msg.sender];
        ethDeposited[msg.sender] = 0;
        payable(msg.sender).sendValue(toRefund);

        emit ETHClaimedBack(msg.sender, toRefund);
    }
}
