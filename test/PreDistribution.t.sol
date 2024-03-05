// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import "../src/contracts/HIGHERToken.sol";
import "../src/contracts/PreDistribution.sol";

contract PreDistributionTest is Test {
    using Arithmetic for uint256;

    HIGHERToken token;
    PreDistribution preDistribution;

    IThrusterRouter02 router =
        IThrusterRouter02(0x98994a9A7a2570367554589189dC9772241650f6);

    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");

    function setUp() public {
        vm.createSelectFork("https://rpc.ankr.com/blast", 382338);
        token = new HIGHERToken("Higher Finance Token", "HIGHER");
        address[] memory premiumWhitelist = new address[](1);
        premiumWhitelist[0] = bob;
        address[] memory whitelist = new address[](2);
        whitelist[0] = alice;
        whitelist[1] = charlie;
        preDistribution = new PreDistribution(
            address(token),
            premiumWhitelist,
            whitelist
        );
        vm.warp(preDistribution.PRE_DISTRIBUTION_START_TIME());

        vm.deal(alice, 100e18);
        vm.deal(bob, 100e18);
        vm.deal(charlie, 100e18);
    }

    function testWhitelistClaim() public {
        vm.prank(alice);
        vm.expectRevert();
        preDistribution.whiteListClaim{value: 0.5e18}();

        vm.prank(alice);
        preDistribution.whiteListClaim{value: 0.15e18}();
        assertEq(preDistribution.higherTokenBalance(alice), 600e18);

        vm.prank(charlie);
        vm.expectRevert();
        preDistribution.whiteListClaim{value: 0.5e18}();

        vm.prank(charlie);
        preDistribution.whiteListClaim{value: 0.15e18}();
        assertEq(preDistribution.higherTokenBalance(charlie), 600e18);

        vm.prank(bob);
        preDistribution.whiteListClaim{value: 0.5e18}();
        assertEq(preDistribution.higherTokenBalance(bob), 4000e18);

        assertEq(preDistribution.higherSold(), 5200e18);
        assertEq(preDistribution.totalEthDeposited(), 0.8e18);
    }

    function testGetHigher() public {
        vm.prank(alice);
        preDistribution.getHigher{value: 1e18}();

        assertEq(preDistribution.higherTokenBalance(alice), 4000e18);

        vm.prank(bob);
        preDistribution.getHigher{value: 1.5e18}();
        assertApproxEqAbs(
            preDistribution.higherTokenBalance(bob),
            5771e18,
            0.1e18
        );

        vm.prank(charlie);
        preDistribution.getHigher{value: 5e18}();
    }

    function testEndPreDistribution() public {
        vm.prank(alice);
        preDistribution.getHigher{value: 25e18}();

        skip(25 hours);

        preDistribution.endPreDistribution();

        vm.prank(alice);
        preDistribution.claimHigher();

        assertGt(token.balanceOf(alice), 0);
    }

    function testEndPreDistributionFail() public {
        vm.prank(alice);
        preDistribution.getHigher{value: 10e18}();

        vm.prank(charlie);
        preDistribution.whiteListClaim{value: 0.15e18}();

        vm.prank(bob);
        preDistribution.whiteListClaim{value: 0.5e18}();

        skip(25 hours);

        preDistribution.endPreDistribution();

        assertFalse(preDistribution.preDistributionSucceeded());

        uint256 balanceBefore = alice.balance;
        vm.prank(alice);
        preDistribution.claimETHBack();
        assertEq(alice.balance - balanceBefore, 10e18);

        balanceBefore = bob.balance;
        vm.prank(bob);
        preDistribution.claimETHBack();
        assertEq(bob.balance - balanceBefore, 0.5e18);

        balanceBefore = charlie.balance;
        vm.prank(charlie);
        preDistribution.claimETHBack();
        assertEq(charlie.balance - balanceBefore, 0.15e18);
    }

    function testSwapAfterPreDistribution() public {
        vm.prank(alice);
        preDistribution.getHigher{value: 50e18}();

        skip(25 hours);
        preDistribution.endPreDistribution();

        IThrusterPair pair = token.getPool();
        assertNotEq(address(pair), address(0));
        if (token.isToken0()) {
            assertEq(pair.token0(), address(token));
            assertEq(pair.token1(), address(router.WETH()));
        } else {
            assertEq(pair.token0(), address(router.WETH()));
            assertEq(pair.token1(), address(token));
        }

        uint256 balanceBefore = token.balanceOf(alice);
        _buyHigherFromAMM(address(this), alice, 0.1 ether);
        uint256 aliceBalance = token.balanceOf(alice);
        assertGt(aliceBalance, balanceBefore);
        console.log("swapped", aliceBalance - balanceBefore);

        uint256 amountToSell = aliceBalance / 2;
        uint256 bobBalanceBefore = bob.balance;
        _sellHigherFromAMM(alice, bob, amountToSell);
        console.log("swapped", bob.balance - bobBalanceBefore);
    }

    function testTwapAfterPreDistribution() public {
        _executePreDistribution();

        skip(1 hours);
        uint256 twapAfterPreDistribution = token.getCurrentTwapPrice();

        _buyHigherFromAMM(address(this), alice, 1 ether);

        skip(30 minutes);

        _buyHigherFromAMM(address(this), bob, 2 ether);
        skip(15 minutes);

        uint256 priceAfterBuys = token.getCurrentTwapPrice();
        assertGt(priceAfterBuys, twapAfterPreDistribution);
        console.log("price before buys", twapAfterPreDistribution);
        console.log("price after buys", priceAfterBuys);
        skip(30 minutes);

        _buyHigherFromAMM(address(this), bob, 10 ether);
        uint256 priceAfterLargeBuy = token.getCurrentTwapPrice();
        console.log("price after large buy", priceAfterLargeBuy);
        assertGt(priceAfterLargeBuy, priceAfterBuys);
    }

    function testRebasing() public {
        vm.prank(bob);
        preDistribution.whiteListClaim{value: 0.5e18}();
        _executePreDistribution();
        vm.prank(bob);
        preDistribution.claimHigher();

        skip(30 minutes);
        _buyHigherFromAMM(address(this), alice, 1 ether);
        skip(4 hours);

        uint256 twapBeforeRebase = token.getCurrentTwapPrice();
        uint256 totalSupplyBefore = token.totalSupply();
        uint256 aliceHoldingsBefore = token.balanceOf(alice).mul(
            twapBeforeRebase
        );
        uint256 bobHoldingsBefore = token.balanceOf(bob).mul(twapBeforeRebase);
        uint256 totalValueBefore = token.totalSupply().mul(twapBeforeRebase);
        token.rebase();
        uint256 totalSupplyAfter = token.totalSupply();
        assertLt(totalSupplyAfter, totalSupplyBefore);
        skip(10 minutes);
        uint256 twapAfterRebase = token.getCurrentTwapPrice();
        assertGt(twapAfterRebase, twapBeforeRebase);
        uint256 aliceHoldingsAfter = token.balanceOf(alice).mul(
            twapAfterRebase
        );
        uint256 bobHoldingsAfter = token.balanceOf(bob).mul(twapAfterRebase);
        uint256 totalValueAfter = token.totalSupply().mul(twapAfterRebase);
        assertApproxEqAbs(totalValueBefore, totalValueAfter, 0.0001e18);
        assertApproxEqAbs(aliceHoldingsBefore, aliceHoldingsAfter, 0.0001e18);
        assertApproxEqAbs(bobHoldingsBefore, bobHoldingsAfter, 0.0001e18);

        console.log("alice holdings before", aliceHoldingsBefore);
        console.log("alice holdings after", aliceHoldingsAfter);

        console.log("bob holdings before", bobHoldingsBefore);
        console.log("bob holdings after", bobHoldingsAfter);

        console.log("total value before", totalValueBefore);
        console.log("total value after", totalValueAfter);

        console.log("total supply before", totalSupplyBefore);
        console.log("total supply after", totalSupplyAfter);

        console.log("twap before rebase", twapBeforeRebase);
        console.log("twap after rebase", twapAfterRebase);
    }

    function testWeeklongRebasing() public {
        vm.prank(bob);
        preDistribution.whiteListClaim{value: 0.5e18}();
        _executePreDistribution();
        vm.prank(bob);
        preDistribution.claimHigher();

        skip(30 minutes);
        for (uint i; i < 30; i++) {
            console.log("i = ", i);
            if (i % 2 == 0) {
                _buyHigherFromAMM(address(this), alice, 1 ether);
            } else {
                uint256 toSell = token.balanceOf(alice) / 2;
                _sellHigherFromAMM(alice, address(this), toSell);
            }
            skip(4 hours);

            uint256 twapBeforeRebase = token.getCurrentTwapPrice();
            uint256 totalValueBefore = token.totalSupply().mul(
                twapBeforeRebase
            );
            uint256 aliceHoldingsBefore = token.balanceOf(alice).mul(
                twapBeforeRebase
            );
            uint256 bobHoldingsBefore = token.balanceOf(bob).mul(
                twapBeforeRebase
            );
            token.rebase();
            skip(10 minutes);
            uint256 twapAfterRebase = token.getCurrentTwapPrice();
            uint256 totalSupplyAfter = token.totalSupply();
            uint256 totalValueAfter = token.totalSupply().mul(twapAfterRebase);
            uint256 aliceHoldingsAfter = token.balanceOf(alice).mul(
                twapAfterRebase
            );
            uint256 bobHoldingsAfter = token.balanceOf(bob).mul(
                twapAfterRebase
            );

            assertApproxEqAbs(totalValueBefore, totalValueAfter, 0.0001e18);
            assertApproxEqAbs(
                aliceHoldingsBefore,
                aliceHoldingsAfter,
                0.0001e18
            );
            assertApproxEqAbs(bobHoldingsBefore, bobHoldingsAfter, 0.0001e18);

            console.log("total supply", totalSupplyAfter);
            console.log("twap", twapAfterRebase);
        }
    }

    function testEndToEnd() public {
        uint256 firstPrivateKey = 1000;

        address[] memory premiumWhitelist = new address[](10);
        address[] memory whitelist = new address[](100);
        address[] memory others = new address[](20);

        for (uint256 i = 0; i < premiumWhitelist.length; i++) {
            premiumWhitelist[i] = vm.addr(firstPrivateKey + i);
            vm.deal(premiumWhitelist[i], 100e18);
        }
        for (uint256 i = 0; i < whitelist.length; i++) {
            whitelist[i] = vm.addr(
                firstPrivateKey + premiumWhitelist.length + i
            );
            vm.deal(whitelist[i], 100e18);
        }
        for (uint256 i = 0; i < others.length; i++) {
            others[i] = vm.addr(
                firstPrivateKey + premiumWhitelist.length + whitelist.length + i
            );
            vm.deal(others[i], 100e18);
        }

        token = new HIGHERToken("Higher Finance Token", "HIGHER");
        preDistribution = new PreDistribution(
            address(token),
            premiumWhitelist,
            whitelist
        );

        for (uint256 i = 0; i < premiumWhitelist.length; i++) {
            vm.prank(premiumWhitelist[i]);
            preDistribution.whiteListClaim{value: 0.5e18}();
        }

        for (uint256 i = 0; i < whitelist.length; i++) {
            vm.prank(whitelist[i]);
            preDistribution.whiteListClaim{value: 0.1e18}();
        }

        for (uint256 i = 0; i < others.length; i++) {
            vm.prank(others[i]);
            preDistribution.getHigher{value: 0.5e18}();
        }

        skip(preDistribution.PRE_DISTRIBUTION_TIME() + 1);
        preDistribution.endPreDistribution();

        for (uint256 i = 0; i < premiumWhitelist.length; i++) {
            vm.prank(premiumWhitelist[i]);
            preDistribution.claimHigher();
            assertGt(token.balanceOf(premiumWhitelist[i]), 0);
        }

        for (uint256 i = 0; i < whitelist.length; i++) {
            vm.prank(whitelist[i]);
            preDistribution.claimHigher();
            assertGt(token.balanceOf(whitelist[i]), 0);
        }

        for (uint256 i = 0; i < others.length; i++) {
            vm.prank(others[i]);
            preDistribution.claimHigher();
            assertGt(token.balanceOf(others[i]), 0);
        }
        uint256 startTime = block.timestamp;

        for (uint i; i < 30; i++) {
            if (i % 2 == 0) {
                _buyHigherFromAMM(address(this), alice, 1 ether);
            } else {
                uint256 toSell = token.balanceOf(alice) / 2;
                _sellHigherFromAMM(alice, address(this), toSell);
            }
            skip(4 hours);

            uint256 twapBeforeRebase = token.getCurrentTwapPrice();
            uint256 totalValueBefore = token.totalSupply().mul(
                twapBeforeRebase
            );
            uint256 aliceHoldingsBefore = token.balanceOf(alice).mul(
                twapBeforeRebase
            );
            uint256 bobHoldingsBefore = token.balanceOf(bob).mul(
                twapBeforeRebase
            );
            token.rebase();
            skip(10 minutes);
            uint256 twapAfterRebase = token.getCurrentTwapPrice();
            uint256 totalValueAfter = token.totalSupply().mul(twapAfterRebase);
            uint256 aliceHoldingsAfter = token.balanceOf(alice).mul(
                twapAfterRebase
            );
            uint256 bobHoldingsAfter = token.balanceOf(bob).mul(
                twapAfterRebase
            );

            assertApproxEqAbs(totalValueBefore, totalValueAfter, 0.0001e18);
            assertApproxEqAbs(
                aliceHoldingsBefore,
                aliceHoldingsAfter,
                0.0001e18
            );
            assertApproxEqAbs(bobHoldingsBefore, bobHoldingsAfter, 0.0001e18);

            console.log("hours elapsed", (block.timestamp - startTime) / 3600);
            console.log("twap", twapAfterRebase);
            console.log(
                "twap appreciation",
                twapAfterRebase.div(twapBeforeRebase)
            );
        }
    }

    function _executePreDistribution() internal {
        vm.prank(alice);
        preDistribution.getHigher{value: 50e18}();

        skip(25 hours);
        preDistribution.endPreDistribution();
    }

    function _buyHigherFromAMM(
        address from,
        address to,
        uint256 amount
    ) internal {
        address[] memory path = new address[](2);
        path[0] = router.WETH();
        path[1] = address(token);
        vm.prank(from);
        router.swapExactETHForTokens{value: amount}(
            0,
            path,
            to,
            block.timestamp
        );
    }

    function _sellHigherFromAMM(
        address from,
        address to,
        uint256 amount
    ) internal {
        address[] memory path = new address[](2);
        path[0] = address(token);
        path[1] = router.WETH();
        vm.prank(from);
        token.approve(address(router), amount);

        vm.prank(from);
        router.swapExactTokensForETH(amount, 0, path, to, block.timestamp);
    }

    receive() external payable {}
}
