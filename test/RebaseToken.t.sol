// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {RebaseToken} from "src/RebaseToken.sol";
import {Vault} from "src/Vault.sol";
import {IRebaseToken} from "src/interfaces/IRebaseToken.sol";
import {Ownable} from "@openzeppelin/contracts/contracts/access/Ownable.sol";
import {IAccessControl} from "@openzeppelin/contracts/contracts/access/AccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken private rebaseToken;
    Vault private vault;

    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.granMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
    }

    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e4, type(uint96).max);
        //1. deposit
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        //2. check our rebase token balance
        uint256 startBalance = rebaseToken.balanceOf(user);
        console2.log("block timestamp 1st: ", block.timestamp);
        console2.log("start balance: ", startBalance);
        assertEq(startBalance, amount);
        //3. warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        console2.log("block timestamp 2nd: ", block.timestamp);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        console2.log("middle balance: ", middleBalance);
        assertGt(middleBalance, startBalance);
        //4. warp the time again with the same amount and check the balance again
        vm.warp(block.timestamp + 1 hours);
        console2.log("block timestamp 3rd: ", block.timestamp);
        uint256 endBalance = rebaseToken.balanceOf(user);
        console2.log("end balance: ", endBalance);
        assertGt(endBalance, middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - startBalance, 1);
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);
        vault.redeem(type(uint256).max);
        assert(address(user).balance == amount);
        assertEq(rebaseToken.balanceOf(user), 0);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 depositAmount, uint256 time) public {
        time = bound(time, 1000, type(uint96).max);
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);
        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();
        vm.warp(block.timestamp + time);
        uint256 balanceAfterSomeTime = rebaseToken.balanceOf(user);
        vm.deal(owner, balanceAfterSomeTime - depositAmount);
        vm.prank(owner);
        addRewardsToVault(balanceAfterSomeTime - depositAmount);
        vm.prank(user);
        vault.redeem(type(uint256).max);

        uint256 ethBalance = address(user).balance;
        assertEq(ethBalance, balanceAfterSomeTime);
        assertGt(ethBalance, depositAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);

        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, amountToSend);

        //check the interest rate should be 5e10 not 4e10 as the owner decreased the interest rate after the first transaction of user

        assertEq(rebaseToken.getUsersInterestRate(user), 5e10);
        assertEq(rebaseToken.getUsersInterestRate(user2), 5e10);
    }

    function testCannotSetInterestRate(uint256 newInterestRate) public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, user));
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testCannotCallMintAndBurn() public {
        uint256 interestRate = rebaseToken.getInterestRate();
        vm.prank(user);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.mint(user, 100, interestRate);
        vm.expectPartialRevert(IAccessControl.AccessControlUnauthorizedAccount.selector);
        rebaseToken.burn(user, 100);
    }

    function testGetThePrincipleAmount(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint256).max);
        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();
        assertEq(amount, rebaseToken.principleBalanceOf(user));

        vm.warp(block.timestamp + 1 hours);

        assertEq(amount, rebaseToken.principleBalanceOf(user));
    }

    function testGetTheRebaseTokenAddress() public view {
        assertEq(vault.getRebaseTokenAddress(), address(rebaseToken));
    }

    function testInterestRateCanOnlyDecrease(uint256 newInterestRate) public {
        uint256 initialInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, initialInterestRate, type(uint256).max);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                RebaseToken.RebaseToken__InterestRateCanOnlyDecrease.selector, initialInterestRate, newInterestRate
            )
        );
        rebaseToken.setInterestRate(newInterestRate);
    }

    function testGrantMintAndBurnRole(uint256 amount, uint256 amountToBurn) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToBurn = bound(amountToBurn, 1e5, amount - 1e5);
        vm.prank(owner);
        rebaseToken.granMintAndBurnRole(user);
        vm.deal(user, amount);
        vm.startPrank(user);
        vault.deposit{value: amount}();
        uint256 startingBalance = rebaseToken.balanceOf(user);
        rebaseToken.burn(user, amountToBurn);
        uint256 endingBalance = rebaseToken.balanceOf(user);

        assertEq(startingBalance - endingBalance, amountToBurn);
    }

    function testTransferFrom(uint256 amount, uint256 amountToSend) public {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5);

        vm.deal(user, amount);
        vm.prank(user);
        vault.deposit{value: amount}();

        address user2 = makeAddr("user2");
        uint256 userBalance = rebaseToken.balanceOf(user);
        uint256 user2Balance = rebaseToken.balanceOf(user2);
        assertEq(userBalance, amount);
        assertEq(user2Balance, 0);

        vm.prank(owner);
        rebaseToken.setInterestRate(4e10);

        vm.prank(user);
        rebaseToken.approve(user2, amountToSend);

        vm.prank(user2);
        rebaseToken.transferFrom(user, user2, amountToSend);

        uint256 userBalanceAfterTransfer = rebaseToken.balanceOf(user);
        uint256 user2BalanceAfterTransfer = rebaseToken.balanceOf(user2);
        assertEq(userBalanceAfterTransfer, userBalance - amountToSend);
        assertEq(user2BalanceAfterTransfer, amountToSend);

        //check the interest rate should be 5e10 not 4e10 as the owner decreased the interest rate after the first transaction of user

        assertEq(rebaseToken.getUsersInterestRate(user), 5e10);
        assertEq(rebaseToken.getUsersInterestRate(user2), 5e10);
    }
}
