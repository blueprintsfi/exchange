// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {gcd} from "core/libraries/Math.sol";
import {HashLib} from "core/libraries/HashLib.sol";
import {BasicBlueprint} from "core/blueprints/BasicBlueprint.sol";
import {IBlueprintManager, TokenOp} from "core/interfaces/IBlueprintManager.sol";
import {FlashAccountingLib as Flash} from "core/libraries/FlashAccountingLib.sol";
import {IfExchange, UserData, Swap, SwapExecution} from "src/interfaces/Ifex.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

function gcd(TokenOp[] calldata ops) pure returns (uint256 res) {
	res = 0;
	for (uint256 i = 0; i < ops.length; i++)
		res = gcd(res, ops[i].amount);
}

contract fExchange is BasicBlueprint, EIP712, IfExchange  {

	mapping (address holder =>
		mapping (address operator =>
			mapping (uint256 delay => UserData data))) public userData;
	mapping (address signer => mapping (bytes32 hash => uint256 filled)) public fill;
	mapping (address signer => mapping (bytes32 hash => uint256 timestamp)) public cancelled;
	mapping (address subaccount => address account) public getMaster;

	/// @dev Type hash for the Withdraw struct
	bytes32 private constant WITHDRAW_TYPEHASH = keccak256(
		"Withdraw(address holder,uint256 delay,uint256 nonce,bytes32 withdrawalsHash)"
	);

	/// @dev Type hash for the TokenOp struct
	bytes32 private constant TOKENOP_TYPEHASH = keccak256(
		"TokenOp(uint256 tokenId,uint256 amount)"
	);

	/// @dev Type hash for the Subaccount declaration
	bytes32 public constant SUBACCOUNT_TYPEHASH = keccak256(
		"SubaccountDeclaration(address holder,address subaccount)"
	);

	constructor(IBlueprintManager _blueprintManager)
		BasicBlueprint(_blueprintManager) {}

	function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
		name = "fExchange";
		version = "1";
	}

	// deposit using cook
	function executeAction(bytes calldata action) external onlyManager returns (
		TokenOp[] memory /*mint*/,
		TokenOp[] memory /*burn*/,
		TokenOp[] memory /*give*/,
		TokenOp[] memory /*take*/
	) {
		(address depositFor, address operator, uint256 delay, TokenOp[] memory deposits) =
			abi.decode(action, (address, address, uint256, TokenOp[]));

		uint256 len = deposits.length;
		for (uint256 i = 0; i < len; i++)
			userData[depositFor][operator][delay].balances[deposits[i].tokenId] += deposits[i].amount;

		emit Deposit(depositFor, operator, delay, deposits);

		return (zero(), zero(), zero(), deposits);
	}

	function getBalance(
		address holder,
		address operator,
		uint256 delay,
		uint256 tokenId
	) external view returns (uint256 balance) {
		balance = userData[holder][operator][delay].balances[tokenId];
	}

	function ragequit(address holder, address operator, uint256 delay) external {
		if (msg.sender != holder && msg.sender != getMaster[holder])
			revert Unauthorized();
		if (userData[holder][operator][delay].ragequitTime != 0)
			revert RagequitAlreadySet();
		userData[holder][operator][delay].ragequitTime = block.timestamp;
		emit Ragequit(holder, operator, delay, msg.sender, block.timestamp);
	}

	function unragequit(address holder, address operator, uint256 delay) external {
		if (msg.sender != holder && msg.sender != getMaster[holder])
			revert Unauthorized();
		if (userData[holder][operator][delay].ragequitTime == 0)
			revert NoRagequitSet();
		userData[holder][operator][delay].ragequitTime = 0;
		emit Unragequit(holder, operator, delay, msg.sender);
	}

	function rageWithdraw(address holder, address operator, uint256 delay, TokenOp[] calldata withdrawals) external {
		if (msg.sender != holder && msg.sender != getMaster[holder])
			revert Unauthorized();
		uint256 ts = userData[holder][operator][delay].ragequitTime;
		if (ts == 0)
			revert NoRagequitSet();
		if (ts + delay >= block.timestamp)
			revert DelayNotPassed();

		uint256 len = withdrawals.length;
		for (uint256 i = 0; i < len; i++) {
			uint256 tokenId = withdrawals[i].tokenId;
			uint256 amount = withdrawals[i].amount;
			userData[holder][operator][delay].balances[tokenId] -= amount;
		}
		blueprintManager.transfer(msg.sender, withdrawals);
	}

	function withdraw(
		address holder,
		address to,
		address operator,
		uint256 delay,
		uint256 nonce,
		TokenOp[] calldata withdrawals,
		bytes calldata signature
	) external {
		if (holder != msg.sender && holder != to) {
			if (msg.sender != getMaster[holder])
				revert Unauthorized();
		}

		bytes32 withdrawalHash = keccak256(abi.encode(
			WITHDRAW_TYPEHASH,
			holder,
			delay,
			nonce,
			_hashTokenOps(withdrawals)
		));

		if (
			!SignatureCheckerLib.isValidSignatureNowCalldata(
				operator,
				_hashTypedData(withdrawalHash),
				signature
			)
		) {
			revert InvalidSignature();
		}

		if (userData[holder][operator][delay].nonce >= nonce) {
			revert InvalidNonce();
		}
		userData[holder][operator][delay].nonce = nonce;

		uint256 len = withdrawals.length;
		for (uint256 i = 0; i < len; i++) {
			uint256 tokenId = withdrawals[i].tokenId;
			uint256 amount = withdrawals[i].amount;
			userData[msg.sender][operator][delay].balances[tokenId] -= amount;
		}
		blueprintManager.transfer(msg.sender, withdrawals);
	}

	function signOrder(bytes32 orderId) external {
		if (fill[msg.sender][orderId] != 0)
			revert OrderAlreadySigned();
		fill[msg.sender][orderId] = 1;

		emit OrderSigned(msg.sender, orderId, 1);
	}

	function initCancel(bytes32[] calldata orderIds) external {
		for (uint256 i = 0; i < orderIds.length; i++) {
			if (cancelled[msg.sender][orderIds[i]] != 0)
				revert OrderAlreadySigned();
			cancelled[msg.sender][orderIds[i]] = block.timestamp;
		}
	}

	function cancel(Swap[] calldata swaps) external {
		for (uint256 i = 0; i < swaps.length; i++) {
			Swap calldata swap = swaps[i];
			bytes32 orderId = keccak256(abi.encode(swap));
			uint256 ts = cancelled[msg.sender][orderId];
			if (ts == 0 || ts + swap.delay >= block.timestamp)
				revert DelayNotPassed();
			fill[msg.sender][orderId] = type(uint256).max;
			emit OrderCanceled(msg.sender, orderId, type(uint256).max);
		}
	}

	function operatorCancel(Swap[] calldata swaps) external {
		for (uint256 i = 0; i < swaps.length; i++) {
			Swap calldata swap = swaps[i];
			require(swap.operator == msg.sender);
			bytes32 orderId = keccak256(abi.encode(swap));
			fill[swap.holder][orderId] = type(uint256).max;
			emit OrderOperatorCanceled(swap.holder, orderId, msg.sender, type(uint256).max);
		}
	}

	function declareSubaccount(address holder, address subaccount, bytes calldata signature) external {
		if (getMaster[subaccount] != address(0))
			revert SubaccountAlreadyDeclared();

		bytes32 subaccountHash = keccak256(abi.encode(
			SUBACCOUNT_TYPEHASH,
			holder,
			subaccount
		));

		require(SignatureCheckerLib.isValidSignatureNowCalldata(
			subaccount,
			_hashTypedData(subaccountHash),
			signature
		));
		getMaster[subaccount] = holder;
	}

	function getSwapData(Swap calldata swap, uint256 previousFill, uint256 newFill) internal pure returns (
		uint256 amountInGcd,
		uint256 amountOutGcd,
		uint256 amountIn
	) {
		amountInGcd = gcd(swap.inputs);
		amountOutGcd = gcd(swap.outputs);

		if (newFill >= amountOutGcd)
			revert ExceedsOutputGcd();

		uint256 previousInput = amountInGcd * previousFill / amountOutGcd;
		uint256 newInput = amountInGcd * newFill / amountOutGcd;

		amountIn = newInput - previousInput;
	}

	function executeSwaps(SwapExecution[] calldata swaps, bytes[] calldata signatures) external {
		UserData storage operatorState = userData[msg.sender][msg.sender][0];
		for (uint256 i = 0; i < swaps.length; i++) {
			SwapExecution calldata swapEx = swaps[i];
			Swap calldata swap = swapEx.swap;
			address holder = swap.holder;
			UserData storage userState = userData[swap.holder][msg.sender][swap.delay];
			UserData storage toState = userData[swap.to][msg.sender][swap.delay]; // todo: consider allowing changing the delay and/or the operator
			bytes32 orderId = keccak256(abi.encode(swap));

			if (block.timestamp > (swap.deadlineAndNonce >> 128))
				revert OrderExpired();
			if (swap.operator != msg.sender)  // todo: operator shouldn't be in calldata then
				revert WrongOperator();

			uint256 previousFill = fill[holder][orderId];

			if (previousFill == 0) {
				require(SignatureCheckerLib.isValidSignatureNowCalldata(
					holder,
					orderId,
					signatures[i]
				));
			} else {
				previousFill--;
			}
			uint256 newFill = previousFill + swapEx.output; // todo revert overflow no message
			fill[holder][orderId] = newFill + 1;
			emit OrderSwapped(holder, orderId, newFill + 1);
			(
				uint256 inGcd,
				uint256 outGcd,
				uint256 amountIn
			) = getSwapData(swap, previousFill, newFill);

			addFlashOps(swap.inputs, getSlot(operatorState), getSlot(userState), inGcd, amountIn);
			addFlashOps(swap.outputs, getSlot(toState), getSlot(operatorState), outGcd, amountIn);
		}

		for (uint256 i = 0; i < swaps.length; i++) {
			Swap calldata swap = swaps[i].swap;
			UserData storage userState = userData[swap.holder][msg.sender][swap.delay];
			UserData storage toState = userData[swap.to][msg.sender][swap.delay];

			settleFlashOps(swap.inputs, userState, operatorState);
			settleFlashOps(swap.outputs, toState, operatorState);
		}
	}

	function addFlashOps(
		TokenOp[] calldata array,
		uint256 add,
		uint256 sub,
		uint256 gcd,
		uint256 amountIn
	) internal {
		for (uint256 i = 0; i < array.length; i++) {
			(uint256 tokenId, uint256 amount) = (array[i].tokenId, array[i].amount);
			amount = amount / gcd * amountIn;

			Flash.addFlashValue(HashLib.hash(tokenId, add), amount);
			Flash.subtractFlashValue(HashLib.hash(tokenId, sub), amount);
		}
	}

	// note: this function just returns the argument, check if this causes additional gas usage
	function getSlot(UserData storage state) internal view returns (uint256 slot) {
		mapping (uint256 => uint256) storage balances = state.balances;
		assembly ("memory-safe") {
			slot := balances.slot
		}
	}

	function settleFlashOp(uint256 id, UserData storage state) internal {
		(uint256 positive, uint256 negative) =
			Flash.readAndNullifyFlashValue(HashLib.hash(id, getSlot(state)));

		if (positive != 0)
			state.balances[id] += positive;
		else if (negative != 0)
			state.balances[id] -= negative;
	}

	function settleFlashOps(
		TokenOp[] calldata array,
		UserData storage state0,
		UserData storage state1
	) internal {
		for (uint256 i = 0; i < array.length; i++) {
			uint256 id = array[i].tokenId;
			settleFlashOp(id, state0);
			settleFlashOp(id, state1);
		}
	}

	/// @dev Helper function to hash an array of TokenOps
	function _hashTokenOps(TokenOp[] calldata ops) internal pure returns (bytes32) {
		if (ops.length == 0) return bytes32(0);
		if (ops.length == 1) {
			return keccak256(abi.encode(
				TOKENOP_TYPEHASH,
				ops[0].tokenId,
				ops[0].amount
			));
		}
		bytes32[] memory hashes = new bytes32[](ops.length);
		for (uint256 i = 0; i < ops.length; i++) {
			hashes[i] = keccak256(abi.encode(
				TOKENOP_TYPEHASH,
				ops[i].tokenId,
				ops[i].amount
			));
		}
		return keccak256(abi.encodePacked(hashes));
	}
}
