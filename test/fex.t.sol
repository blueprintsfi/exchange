// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "forge-std/Test.sol";
import "../src/fex.sol";
import {TokenOp} from "../lib/core/src/blueprints/BasicBlueprint.sol";
import {BlueprintManager, BlueprintCall, HashLib} from "../lib/core/src/BlueprintManager.sol";

contract fExchangeFuzzTest is Test {
	// Using tabs for indentation.
	fExchange public exchange;
	BlueprintManager public blueprintManager;
	address public user;
	address public operator;
	uint256 public constant delay = 1 days;

	// setUp deploys the blueprint manager and fExchange and sets initial token balances.
	function setUp() public {
		// Deploy BlueprintManager and fExchange.
		blueprintManager = new BlueprintManager();
		exchange = new fExchange(blueprintManager);
		user = makeAddr("user");
		operator = makeAddr("operator");
	}

	/// @dev Helper to mint tokens and prepare them for testing
	function prepareTokensForTest(uint256 amount, uint256 seed) internal returns (uint256 tokenId) {
		// Mint tokens to the test contract
		blueprintManager.mint(address(this), seed, amount);
		tokenId = HashLib.hash(address(this), seed);
		// Transfer tokens to user
		blueprintManager.transfer(user, tokenId, amount);
	}

	/// @dev Helper to encode a deposit action.
	/// The deposit action encodes (depositFor, operator, delay, deposits).
	function encodeDepositAction(TokenOp[] memory deposits) internal view returns (bytes memory) {
		return abi.encode(user, operator, delay, deposits);
	}

	/// @dev Helper to execute a deposit via BlueprintManager.cook(), which simulates a realistic call.
	function executeDepositViaManager(bytes memory action) internal {
		BlueprintCall[] memory calls = new BlueprintCall[](1);
		calls[0] = BlueprintCall({
			blueprint: address(exchange),
			action: action,
			sender: address(0),
			checksum: 0
		});
		// Simulate the user calling cook().
		vm.prank(user);
		blueprintManager.cook(user, calls);
	}

	/// @notice Test that multiple deposits accumulate correctly.
	function test_MultipleDepositsAccumulation() public {
		uint256 id = prepareTokensForTest(10000, 0);

		// Deposit 50 tokens.
		TokenOp[] memory dep1 = new TokenOp[](1);
		dep1[0] = TokenOp(id, 50);
		bytes memory act1 = encodeDepositAction(dep1);
		executeDepositViaManager(act1);

		// Deposit another 25 tokens.
		TokenOp[] memory dep2 = new TokenOp[](1);
		dep2[0] = TokenOp(id, 25);
		bytes memory act2 = encodeDepositAction(dep2);
		executeDepositViaManager(act2);

		uint256 bal = exchange.getBalance(user, operator, delay, id);
		assertEq(bal, 75, "Accumulated deposit should be 75");
	}

	/// @notice Test that deposits for different operators are stored separately.
	function test_DepositDifferentOperators() public {
		uint256 id = prepareTokensForTest(10000, 0);
		TokenOp[] memory dep = new TokenOp[](1);
		dep[0] = TokenOp(id, 100);

		// Deposit for operatorA.
		address operatorA = makeAddr("operatorA");
		{
			bytes memory actA = abi.encode(user, operatorA, delay, dep);
			BlueprintCall[] memory calls = new BlueprintCall[](1);
			calls[0] = BlueprintCall({
				blueprint: address(exchange),
				action: actA,
				sender: address(0),
				checksum: 0
			});
			vm.prank(user);
			blueprintManager.cook(user, calls);
		}

		// Deposit for operatorB.
		address operatorB = makeAddr("operatorB");
		{
			bytes memory actB = abi.encode(user, operatorB, delay, dep);
			BlueprintCall[] memory calls = new BlueprintCall[](1);
			calls[0] = BlueprintCall({
				blueprint: address(exchange),
				action: actB,
				sender: address(0),
				checksum: 0
			});
			vm.prank(user);
			blueprintManager.cook(user, calls);
		}

		uint256 balA = exchange.getBalance(user, operatorA, delay, id);
		uint256 balB = exchange.getBalance(user, operatorB, delay, id);
		assertEq(balA, 100, "OperatorA balance should be 100");
		assertEq(balB, 100, "OperatorB balance should be 100");
	}

	/// @notice Test that calling deposit with an empty array leaves balance unchanged.
	function test_DepositEmptyArray() public {
		TokenOp[] memory dep = new TokenOp[](0);
		bytes memory act = abi.encode(user, operator, delay, dep);
		executeDepositViaManager(act);
		uint256 bal = exchange.getBalance(user, operator, delay, 1);
		assertEq(bal, 0, "Empty deposit should leave balance unchanged");
	}

	/// @notice Test that depositing a zero amount leaves balance unchanged.
	function test_DepositZeroAmount() public {
		TokenOp[] memory dep = new TokenOp[](1);
		dep[0] = TokenOp(1, 0);
		bytes memory act = abi.encode(user, operator, delay, dep);
		executeDepositViaManager(act);
		uint256 bal = exchange.getBalance(user, operator, delay, 1);
		assertEq(bal, 0, "Deposit of zero amount should leave balance unchanged");
	}

	/// @notice Fuzz test for a single deposit.
	function test_FuzzDeposit(uint256 amount) public {
		vm.assume(amount > 0 && amount <= 1000);
		uint256 id = prepareTokensForTest(1000, 0);
		TokenOp[] memory dep = new TokenOp[](1);
		dep[0] = TokenOp(id, amount);
		bytes memory act = abi.encode(user, operator, delay, dep);
		executeDepositViaManager(act);
		uint256 bal = exchange.getBalance(user, operator, delay, id);
		assertEq(bal, amount, "Fuzz deposit should record correct balance");
	}

	/// @notice Fuzz test for multiple deposits accumulation.
	function test_FuzzMultipleDepositsAccumulation(uint256 amount1, uint256 amount2) public {
		amount1 = bound(amount1, 1, 500);
		amount2 = bound(amount2, 1, 500);
		uint256 id = prepareTokensForTest(1000, 0);
		TokenOp[] memory dep1 = new TokenOp[](1);
		dep1[0] = TokenOp(id, amount1);
		bytes memory act1 = encodeDepositAction(dep1);
		executeDepositViaManager(act1);

		TokenOp[] memory dep2 = new TokenOp[](1);
		dep2[0] = TokenOp(id, amount2);
		bytes memory act2 = encodeDepositAction(dep2);
		executeDepositViaManager(act2);

		uint256 expected = amount1 + amount2;
		uint256 bal = exchange.getBalance(user, operator, delay, id);
		assertEq(bal, expected, "Fuzz accumulation incorrect");
	}

	/// @notice Test that ragequit reverts if already set.
	function test_RagequitAlreadySetReverts() public {
		uint256 id = prepareTokensForTest(1000, 0);
		TokenOp[] memory dep = new TokenOp[](1);
		dep[0] = TokenOp(id, 100);
		bytes memory act = abi.encode(user, operator, delay, dep);
		executeDepositViaManager(act);

		vm.prank(user);
		exchange.ragequit(user, operator, delay);

		vm.prank(user);
		vm.expectRevert();
		exchange.ragequit(user, operator, delay);
	}

	/// @notice Test that unragequit reverts if no ragequit is set.
	function test_UnragequitWithoutRagequitReverts() public {
		vm.prank(user);
		vm.expectRevert();
		exchange.unragequit(user, operator, delay);
	}

	/// @notice Test ragequit and unragequit via BlueprintManager (realistic use case).
	function test_RagequitAndUnragequit() public {
		uint256 id = prepareTokensForTest(1000, 0);
		TokenOp[] memory dep = new TokenOp[](1);
		dep[0] = TokenOp(id, 200);
		bytes memory act = abi.encode(user, operator, delay, dep);
		executeDepositViaManager(act);

		vm.prank(user);
		exchange.ragequit(user, operator, delay);
		(, uint256 rqTime) = exchange.userData(user, operator, delay);
		assertTrue(rqTime != 0, "Ragequit time should be set");

		vm.prank(user);
		exchange.unragequit(user, operator, delay);
		(, uint256 rqTimeAfter) = exchange.userData(user, operator, delay);
		assertEq(rqTimeAfter, 0, "Ragequit time should be cleared");
	}

	/// @notice Test that rageWithdraw reverts if called before delay has passed.
	function test_RageWithdrawBeforeDelayReverts() public {
		uint256 id = prepareTokensForTest(1000, 0);
		TokenOp[] memory dep = new TokenOp[](1);
		dep[0] = TokenOp(id, 100);
		bytes memory act = abi.encode(user, operator, delay, dep);
		executeDepositViaManager(act);

		vm.prank(user);
		exchange.ragequit(user, operator, delay);

		TokenOp[] memory wd = new TokenOp[](1);
		wd[0] = TokenOp(id, 50);
		vm.prank(user);
		vm.expectRevert();
		exchange.rageWithdraw(user, operator, delay, wd);
	}

	/// @notice Test that rageWithdraw works after the delay has passed.
	function test_RageWithdrawAfterDelayWorks() public {
		uint256 id = prepareTokensForTest(1000, 0);
		TokenOp[] memory dep = new TokenOp[](1);
		dep[0] = TokenOp(id, 200);
		bytes memory act = abi.encode(user, operator, delay, dep);
		executeDepositViaManager(act);

		vm.prank(user);
		exchange.ragequit(user, operator, delay);
		// Warp time past the delay.
		vm.warp(block.timestamp + delay + 1);

		TokenOp[] memory wd = new TokenOp[](1);
		wd[0] = TokenOp(id, 150);
		vm.prank(user);
		exchange.rageWithdraw(user, operator, delay, wd);
		uint256 bal = exchange.getBalance(user, operator, delay, id);
		assertEq(bal, 50, "After rageWithdraw, remaining balance should be 50");
	}

	/// @notice Fuzz test for signOrder.
	function test_FuzzSignOrder(bytes32 orderId) public {
		vm.prank(user);
		exchange.signOrder(orderId);
		uint256 fillStatus = exchange.fill(user, orderId);
		assertEq(fillStatus, 1, "Order should be signed and fill set to 1");
	}

	/// @notice Test that signing an already signed order reverts.
	function test_SignOrderDuplicateReverts() public {
		bytes32 orderId = keccak256("test_order");
		vm.prank(user);
		exchange.signOrder(orderId);
		vm.prank(user);
		vm.expectRevert();
		exchange.signOrder(orderId);
	}

	/// @notice Test that initCancel sets cancellation timestamps and cancel marks the order as canceled.
	function test_InitCancelAndCancel() public {
		// Construct a dummy Swap.
		Swap memory swap;
		swap.holder = user;
		swap.operator = operator;
		swap.delay = delay;
		// Set deadlineAndNonce: shift a future timestamp left 128 bits and OR with nonce 1.
		swap.deadlineAndNonce = (block.timestamp + 1000) << 128 | 1;
		swap.to = user;
		TokenOp[] memory inputs = new TokenOp[](1);
		uint256 id = prepareTokensForTest(1000, 1);
		inputs[0] = TokenOp(id, 100);
		swap.inputs = inputs;
		TokenOp[] memory outputs = new TokenOp[](1);
		outputs[0] = TokenOp(id, 200);
		swap.outputs = outputs;

		bytes32 orderId = keccak256(abi.encode(swap));

		// Initialize cancellation.
		bytes32[] memory orderIds = new bytes32[](1);
		orderIds[0] = orderId;
		vm.prank(user);
		exchange.initCancel(orderIds);

		// Warp time past the delay period
		vm.warp(block.timestamp + delay + 1);

		// Cancel the order.
		Swap[] memory swaps = new Swap[](1);
		swaps[0] = swap;
		vm.prank(user);
		exchange.cancel(swaps);

		uint256 fillStatus = exchange.fill(user, orderId);
		assertEq(fillStatus, type(uint256).max, "Cancel should set fill to max");
	}

	/// @notice Test subaccount declaration.
	function test_DeclareSubaccount() public {
		uint256 subPk = uint256(keccak256(abi.encodePacked("subaccount")));
		address subAddr = vm.addr(subPk);

		// Create the subaccount declaration hash
		bytes32 subaccountHash = keccak256(abi.encode(
			exchange.SUBACCOUNT_TYPEHASH(),
			user,
			subAddr
		));

		// Compute the domain separator exactly as EIP-712 requires.
		bytes32 domainSeparator = keccak256(
			abi.encode(
				keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
				keccak256(bytes("fExchange")),
				keccak256(bytes("1")),
				block.chainid,
				address(exchange)
			)
		);
		
		// Manually compute the digest matching EIP-712
		bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, subaccountHash));
		
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(subPk, digest);
		bytes memory signature = abi.encodePacked(r, s, v);

		vm.prank(user);
		exchange.declareSubaccount(user, subAddr, signature);
		address master = exchange.getMaster(subAddr);
		assertEq(master, user, "Subaccount master should be set to user");
	}

	/// @notice Test operator cancel for a swap.
	function test_OperatorCancel() public {
		// Construct a dummy Swap.
		Swap memory swap;
		swap.holder = user;
		swap.operator = operator;
		swap.delay = delay;
		swap.deadlineAndNonce = (block.timestamp + 1000) << 128 | 1;
		swap.to = user;
		TokenOp[] memory inputs = new TokenOp[](1);
		uint256 id = prepareTokensForTest(1000, 2);
		inputs[0] = TokenOp(id, 100);
		swap.inputs = inputs;
		TokenOp[] memory outputs = new TokenOp[](1);
		outputs[0] = TokenOp(id, 200);
		swap.outputs = outputs;

		Swap[] memory swaps = new Swap[](1);
		swaps[0] = swap;
		vm.prank(operator);
		exchange.operatorCancel(swaps);

		bytes32 orderId = keccak256(abi.encode(swap));
		uint256 fillStatus = exchange.fill(user, orderId);
		assertEq(fillStatus, type(uint256).max, "Operator cancel should set fill to max");
	}

	/// @notice Test that multiple deposits accumulate correctly.
	function test_FuzzMultipleDeposits(uint256 amount1, uint256 amount2) public {
		vm.assume(amount1 > 0 && amount1 <= 5000);
		vm.assume(amount2 > 0 && amount2 <= 5000);
		uint256 id = prepareTokensForTest(10000, 0);

		// Deposit amount1 tokens
		TokenOp[] memory dep1 = new TokenOp[](1);
		dep1[0] = TokenOp(id, amount1);
		bytes memory act1 = encodeDepositAction(dep1);
		executeDepositViaManager(act1);

		// Deposit amount2 tokens
		TokenOp[] memory dep2 = new TokenOp[](1);
		dep2[0] = TokenOp(id, amount2);
		bytes memory act2 = encodeDepositAction(dep2);
		executeDepositViaManager(act2);

		uint256 bal = exchange.getBalance(user, operator, delay, id);
		assertEq(bal, amount1 + amount2, "Accumulated deposit incorrect");
	}

	/// @notice Test that deposits for different operators are stored separately.
	function test_FuzzDepositDifferentOperators(uint256 amount1, uint256 amount2) public {
		amount1 = bound(amount1, 1, 5000);
		amount2 = bound(amount2, 1, 5000);
		uint256 id = prepareTokensForTest(10000, 0);

		// Deposit for operatorA
		address operatorA = makeAddr("operatorA");
		{
			TokenOp[] memory dep = new TokenOp[](1);
			dep[0] = TokenOp(id, amount1);
			bytes memory actA = abi.encode(user, operatorA, delay, dep);
			executeDepositViaManager(actA);
		}

		// Deposit for operatorB
		address operatorB = makeAddr("operatorB");
		{
			TokenOp[] memory dep = new TokenOp[](1);
			dep[0] = TokenOp(id, amount2);
			bytes memory actB = abi.encode(user, operatorB, delay, dep);
			executeDepositViaManager(actB);
		}

		uint256 balA = exchange.getBalance(user, operatorA, delay, id);
		uint256 balB = exchange.getBalance(user, operatorB, delay, id);
		assertEq(balA, amount1, "OperatorA balance incorrect");
		assertEq(balB, amount2, "OperatorB balance incorrect");
	}

	/// @notice Test that rageWithdraw works after the delay has passed.
	function test_FuzzRageWithdrawAfterDelay(uint256 depositAmount, uint256 withdrawAmount) public {
		depositAmount = bound(depositAmount, 1, 1000);
		withdrawAmount = bound(withdrawAmount, 1, depositAmount);

		uint256 id = prepareTokensForTest(1000, 0);
		TokenOp[] memory dep = new TokenOp[](1);
		dep[0] = TokenOp(id, depositAmount);
		bytes memory act = abi.encode(user, operator, delay, dep);
		executeDepositViaManager(act);

		vm.prank(user);
		exchange.ragequit(user, operator, delay);
		// Warp time past the delay
		vm.warp(block.timestamp + delay + 1);

		TokenOp[] memory wd = new TokenOp[](1);
		wd[0] = TokenOp(id, withdrawAmount);
		vm.prank(user);
		exchange.rageWithdraw(user, operator, delay, wd);
		uint256 bal = exchange.getBalance(user, operator, delay, id);
		assertEq(bal, depositAmount - withdrawAmount, "Remaining balance incorrect after rageWithdraw");
	}

	/// @notice Test that initCancel and cancel work with fuzzed inputs
	function test_FuzzInitCancelAndCancel(uint256 inputAmount, uint256 outputAmount, uint256 futureTime) public {
		inputAmount = bound(inputAmount, 1, 1000);
		outputAmount = bound(outputAmount, 1, 1000);
		futureTime = bound(futureTime, block.timestamp + 1, block.timestamp + 1 days);

		// Construct a Swap with fuzzed values
		Swap memory swap;
		swap.holder = user;
		swap.operator = operator;
		swap.delay = delay;
		swap.deadlineAndNonce = futureTime << 128 | 1;
		swap.to = user;

		TokenOp[] memory inputs = new TokenOp[](1);
		uint256 id = prepareTokensForTest(1000, 1);
		inputs[0] = TokenOp(id, inputAmount);
		swap.inputs = inputs;

		TokenOp[] memory outputs = new TokenOp[](1);
		outputs[0] = TokenOp(id, outputAmount);
		swap.outputs = outputs;

		bytes32 orderId = keccak256(abi.encode(swap));

		// Initialize cancellation
		bytes32[] memory orderIds = new bytes32[](1);
		orderIds[0] = orderId;
		vm.prank(user);
		exchange.initCancel(orderIds);

		// Warp time past the delay period
		vm.warp(block.timestamp + delay + 1);

		// Cancel the order
		Swap[] memory swaps = new Swap[](1);
		swaps[0] = swap;
		vm.prank(user);
		exchange.cancel(swaps);

		uint256 fillStatus = exchange.fill(user, orderId);
		assertEq(fillStatus, type(uint256).max, "Cancel should set fill to max");
	}

	/// @notice Test withdraw signature verification with TokenOp array
	function test_WithdrawSignature() public {
		uint256 id = prepareTokensForTest(1000, 0);
		TokenOp[] memory withdrawals = new TokenOp[](1);
		withdrawals[0] = TokenOp(id, 100);

		// Create the withdraw hash
		bytes32 withdrawHash = keccak256(abi.encode(
			exchange.WITHDRAW_TYPEHASH(),
			user,
			delay,
			1, // nonce
			withdrawals
		));

		// Compute the domain separator exactly as EIP-712 requires
		bytes32 domainSeparator = keccak256(
			abi.encode(
				keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
				keccak256(bytes("fExchange")),
				keccak256(bytes("1")),
				block.chainid,
				address(exchange)
			)
		);
		
		// Manually compute the digest matching EIP-712
		bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, withdrawHash));
		
		// Sign with operator's key
		uint256 operatorPk = uint256(keccak256(abi.encodePacked("operator")));
		operator = vm.addr(operatorPk);
		(uint8 v, bytes32 r, bytes32 s) = vm.sign(operatorPk, digest);
		bytes memory signature = abi.encodePacked(r, s, v);

		// First deposit some tokens
		TokenOp[] memory dep = new TokenOp[](1);
		dep[0] = TokenOp(id, 100);
		bytes memory act = abi.encode(user, operator, delay, dep);
		executeDepositViaManager(act);

		// Execute withdraw
		vm.prank(user);
		exchange.withdraw(user, user, operator, delay, 1, withdrawals, signature);

		uint256 bal = exchange.getBalance(user, operator, delay, id);
		assertEq(bal, 0, "Balance should be 0 after withdraw");
	}
}
