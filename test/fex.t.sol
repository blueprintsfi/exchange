// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/fex.sol"; // Make sure the path is correct.
import {TokenOp} from "../lib/core/src/blueprints/BasicBlueprint.sol";
import {BlueprintManager} from "../lib/core/src/BlueprintManager.sol";

contract fExchangeSimplifiedTest is Test {
    fExchange public exchange;
    BlueprintManager public blueprintManager;
    address public user;
    address public operator;
    uint256 public constant delay = 1 days;

    function setUp() public {
        // Deploy BlueprintManager and fExchange.
        blueprintManager = new BlueprintManager();
        exchange = new fExchange(blueprintManager);
        user = makeAddr("user");
        operator = makeAddr("operator");
        vm.deal(user, 100 ether);
        vm.deal(operator, 100 ether);

        // Set up the blueprint manager for the user.
        vm.startPrank(user);
        blueprintManager.setOperator(address(blueprintManager), true);
        // Mint a moderate amount for tokenId 1.
        blueprintManager.mint(user, 1, 10000);
        // Approve the exchange as an operator.
        blueprintManager.setOperator(address(exchange), true);
        vm.stopPrank();
    }

    /// @dev Helper to execute a deposit action.
    /// Since executeAction is protected by onlyManager, we simulate a call from the blueprint manager.
    function executeDeposit(TokenOp[] memory deposits) internal {
        bytes memory action = abi.encode(user, operator, delay, deposits);
        vm.prank(address(blueprintManager));
        exchange.executeAction(action);
    }

    /// @notice Test that multiple deposits accumulate correctly.
    function test_MultipleDepositsAccumulation() public {
        // First deposit: 50 tokens.
        TokenOp[] memory deposits1 = new TokenOp[](1);
        deposits1[0] = TokenOp(1, 50);
        executeDeposit(deposits1);

        // Second deposit: 25 tokens.
        TokenOp[] memory deposits2 = new TokenOp[](1);
        deposits2[0] = TokenOp(1, 25);
        executeDeposit(deposits2);

        uint256 bal = exchange.getBalance(user, operator, delay, 1);
        assertEq(bal, 75, "Accumulated deposit should be 75");
    }

    /// @notice Test that deposits for different operators are stored separately.
    function test_DepositDifferentOperators() public {
        TokenOp[] memory deposits = new TokenOp[](1);
        deposits[0] = TokenOp(1, 100);

        // Deposit for operatorA.
        address operatorA = makeAddr("operatorA");
        {
            bytes memory actionA = abi.encode(user, operatorA, delay, deposits);
            vm.prank(address(blueprintManager));
            exchange.executeAction(actionA);
        }
        // Deposit for operatorB.
        address operatorB = makeAddr("operatorB");
        {
            bytes memory actionB = abi.encode(user, operatorB, delay, deposits);
            vm.prank(address(blueprintManager));
            exchange.executeAction(actionB);
        }

        uint256 balA = exchange.getBalance(user, operatorA, delay, 1);
        uint256 balB = exchange.getBalance(user, operatorB, delay, 1);
        assertEq(balA, 100, "OperatorA balance should be 100");
        assertEq(balB, 100, "OperatorB balance should be 100");
    }

    /// @notice Test that calling deposit with an empty array does not update the balance.
    function test_DepositEmptyArray() public {
        TokenOp[] memory deposits = new TokenOp[](0);
        bytes memory action = abi.encode(user, operator, delay, deposits);
        vm.prank(address(blueprintManager));
        // This call will not revert in the current implementation.
        exchange.executeAction(action);
        uint256 bal = exchange.getBalance(user, operator, delay, 1);
        assertEq(bal, 0, "Empty deposit should leave balance unchanged");
    }

    /// @notice Test that depositing a zero amount does not update the balance.
    function test_DepositZeroAmount() public {
        TokenOp[] memory deposits = new TokenOp[](1);
        deposits[0] = TokenOp(1, 0);
        bytes memory action = abi.encode(user, operator, delay, deposits);
        vm.prank(address(blueprintManager));
        exchange.executeAction(action);
        uint256 bal = exchange.getBalance(user, operator, delay, 1);
        assertEq(bal, 0, "Deposit of zero amount should leave balance unchanged");
    }

    /// @notice Test depositing a large (but moderate) amount.
    function test_DepositMaxAmount() public {
        uint256 depositAmount = 10000;
        TokenOp[] memory deposits = new TokenOp[](1);
        deposits[0] = TokenOp(1, depositAmount);
        executeDeposit(deposits);
        uint256 bal = exchange.getBalance(user, operator, delay, 1);
        assertEq(bal, depositAmount, "Max deposit not recorded correctly");
    }

    /// @notice Test ragequit by the deposit holder and then unragequit.
    function test_RagequitAndUnragequit() public {
        // Deposit tokens.
        TokenOp[] memory deposits = new TokenOp[](1);
        deposits[0] = TokenOp(1, 200);
        executeDeposit(deposits);

        // Ragequit by the user.
        vm.prank(user);
        exchange.ragequit(operator, delay);
        (, uint256 rqTime) = exchange.userData(user, operator, delay);
        assertTrue(rqTime != 0, "Ragequit time should be set");

        // Unragequit by the user.
        vm.prank(user);
        exchange.unragequit(operator, delay);
        (, uint256 rqTimeAfter) = exchange.userData(user, operator, delay);
        assertEq(rqTimeAfter, 0, "Ragequit time should be cleared");
    }

    /// @notice Test that a call to ragequit from an address other than the deposit holder
    /// sets the ragequit time for that caller (since no access control is implemented).
    function test_RagequitUnauthorized() public {
        // Deposit tokens as user.
        TokenOp[] memory deposits = new TokenOp[](1);
        deposits[0] = TokenOp(1, 100);
        executeDeposit(deposits);

        // Now simulate an "unauthorized" ragequit by the operator.
        // In the current implementation, this call does NOT revert.
        vm.prank(operator);
        exchange.ragequit(operator, delay);
        (, uint256 rqTime) = exchange.userData(operator, operator, delay);
        assertTrue(rqTime != 0, "Operator ragequit should be recorded (per current implementation)");
    }
}
