// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {gcd} from "core/libraries/Math.sol";
import {HashLib} from "core/libraries/HashLib.sol";
import {FlashAccountingLib as Flash} from "core/libraries/FlashAccountingLib.sol";
import {BasicBlueprint} from "core/blueprints/BasicBlueprint.sol";
import {IBlueprintManager, TokenOp} from "core/interfaces/IBlueprintManager.sol";
import {TypedDataHashLib} from "./libraries/TypedDataHashLib.sol";
import {TypeHashes} from "./libraries/TypeHashes.sol";
import {IExchange, UserData, Swap, SwapExecution} from "src/interfaces/IExchange.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

function gcd(TokenOp[] calldata ops) pure returns (uint256 res) {
	res = 0;
	for (uint256 i = 0; i < ops.length; i++)
		res = gcd(res, ops[i].amount);
}

function isValidSig(address signer, bytes32 hash, bytes calldata signature) returns (bool) {
	return SignatureCheckerLib.isValidSignatureNowCalldata(signer, hash, signature);
}

contract Exchange is BasicBlueprint, IExchange, EIP712 {

	mapping (address holder =>
		mapping (address operator =>
			mapping (uint256 delay => UserData data))) public userData;
	mapping (address holder =>
		mapping (uint256 subaccount =>
			mapping (address signer => bool isSigner))) public signers;
	mapping (address signer => mapping (bytes32 hash => uint256 filled)) public fill;
	mapping (address signer => mapping (bytes32 hash => uint256 timestamp)) public cancelled;
	mapping (address subaccount => address account) public getMaster;

	constructor(IBlueprintManager _blueprintManager)
		BasicBlueprint(_blueprintManager)
		EIP712() {}

	function _domainNameAndVersion() internal pure override returns (
		string memory name,
		string memory version
	) {
		name = "Exchange";
		version = "1";
	}

	// deposit using cook
	function executeAction(bytes calldata action) external onlyManager returns (
		TokenOp[] memory /*mint*/,
		TokenOp[] memory /*burn*/,
		TokenOp[] memory /*give*/,
		TokenOp[] memory /*take*/
	) {
		(address depositFor, uint256 subaccount, address operator, uint256 delay, TokenOp[] memory deposits) =
			abi.decode(action, (address, uint256, address, uint256, TokenOp[]));

		mapping (uint256 tokenId => uint256 balance) storage balances =
			userData[depositFor][operator][delay].balances[subaccount];

		uint256 len = deposits.length;
		for (uint256 i = 0; i < len; i++)
			balances[deposits[i].tokenId] += deposits[i].amount;

		emit Deposit(depositFor, operator, delay, deposits);

		return (zero(), zero(), zero(), deposits);
	}

	function getBalance(
		address holder,
		uint256 subaccount,
		address operator,
		uint256 delay,
		uint256 tokenId
	) external view returns (uint256 balance) {
		balance = userData[holder][operator][delay].balances[subaccount][tokenId];
	}

	function hasAccess(address sender, address holder, uint256 subaccount) public view returns (bool) {
		if (sender == holder)
			return true;
		if (subaccount != 0)
			return signers[holder][subaccount][sender];
		return signers[holder][0][sender];
	}

	function ragequit(address holder, address operator, uint256 delay) external {
		if (!hasAccess(msg.sender, holder, 0))
			revert Unauthorized();
		if (userData[holder][operator][delay].ragequitTime != 0)
			revert RagequitAlreadySet();
		userData[holder][operator][delay].ragequitTime = block.timestamp;
		emit Ragequit(holder, operator, delay, msg.sender, block.timestamp);
	}

	function unragequit(address holder, address operator, uint256 delay) external {
		if (!hasAccess(msg.sender, holder, 0))
			revert Unauthorized();
		if (userData[holder][operator][delay].ragequitTime == 0)
			revert NoRagequitSet();
		userData[holder][operator][delay].ragequitTime = 0;
		emit Unragequit(holder, operator, delay, msg.sender);
	}

	function rageWithdraw(
		address holder,
		uint256 subaccount,
		address to,
		address operator,
		uint256 delay,
		TokenOp[] calldata withdrawals
	) external {
		if (!hasAccess(msg.sender, holder, 0))
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
			userData[holder][operator][delay].balances[subaccount][tokenId] -= amount;
		}

		blueprintManager.transfer(to, withdrawals);
		emit RageWithdraw(holder, subaccount, to, operator, delay, withdrawals);
	}

	function withdraw(
		address holder,
		uint256 subaccount,
		address to,
		address operator,
		uint256 delay,
		uint256 nonce,
		TokenOp[] calldata withdrawals,
		bytes calldata signature
	) external {
		if (holder != to) {
  			if (!hasAccess(msg.sender, holder, subaccount))
    			revert Unauthorized();
  		}

		bytes32 withdrawalHash = TypedDataHashLib.hashWithdraw(
			holder,
			subaccount,
			delay,
			nonce,
			withdrawals
		);

		if (!isValidSig(operator, _hashTypedData(withdrawalHash), signature))
			revert InvalidSignature();

		if (userData[holder][operator][delay].nonce >= nonce)
			revert InvalidNonce();

		userData[holder][operator][delay].nonce = nonce;

		uint256 len = withdrawals.length;
		for (uint256 i = 0; i < len; i++) {
			uint256 tokenId = withdrawals[i].tokenId;
			uint256 amount = withdrawals[i].amount;
			userData[holder][operator][delay].balances[subaccount][tokenId] -= amount;
		}
		blueprintManager.transfer(to, withdrawals);
		emit Withdraw(holder, subaccount, to, operator, delay, withdrawals);
	}

	function signOrder(bytes32[] calldata orderIds) external {
		for(uint256 i = 0; i < orderIds.length; i++) {
			if (fill[msg.sender][orderIds[i]] != 0)
				revert OrderAlreadySigned();
			fill[msg.sender][orderIds[i]] = 1;
			emit OrderSigned(msg.sender, orderIds[i]);
		}
	}

	function initCancel(bytes32[] calldata orderIds) external {
		for (uint256 i = 0; i < orderIds.length; i++) {
			if (cancelled[msg.sender][orderIds[i]] != 0)
				revert OrderCancelAlreadyInitialized();
			cancelled[msg.sender][orderIds[i]] = block.timestamp;
			emit InitCancel(msg.sender, orderIds[i]);
		}
	}

	function cancel(Swap[] calldata swaps) external {
		for (uint256 i = 0; i < swaps.length; i++) {
			Swap calldata swap = swaps[i];
			bytes32 orderId = keccak256(abi.encode(swap));
			uint256 ts = cancelled[msg.sender][orderId];
			if (ts + swap.delay >= block.timestamp)
				revert DelayNotPassed();
			if (ts == 0)
				revert OrderCancelNotInitialized();
			fill[msg.sender][orderId] = type(uint256).max;
			emit OrderCanceled(msg.sender, orderId);
		}
	}

	function operatorCancel(Swap[] calldata swaps) external {
		for (uint256 i = 0; i < swaps.length; i++) {
			Swap calldata swap = swaps[i];
			require(swap.operator == msg.sender);
			bytes32 orderId = keccak256(abi.encode(swap));
			fill[swap.holder][orderId] = type(uint256).max;
			emit OrderOperatorCanceled(swap.holder, orderId, msg.sender);
		}
	}

	function addSigner(
		address holder,
		uint256 subaccount,
		address signer,
		uint256 deadline,
		bytes calldata signature
	) external {
		if (!hasAccess(msg.sender, holder, 0)) {
			if (block.timestamp > deadline)
				revert DeadlinePassed();

			bytes32 subaccountHash = TypedDataHashLib.hashAddSigner(
				holder,
				subaccount,
				signer,
				deadline
			);

			if (!isValidSig(holder, _hashTypedData(subaccountHash), signature))
				revert InvalidSignature();
		}

		signers[holder][subaccount][signer] = true;
		emit AddSigner(holder, subaccount, signer);
	}

	function removeSigner(
		address holder,
		uint256 subaccount,
		address signer,
		uint256 deadline,
		bytes calldata signature
	) external {
		if (!hasAccess(msg.sender, holder, 0)) {
			if (block.timestamp > deadline)
				revert DeadlinePassed();

			bytes32 subaccountHash = TypedDataHashLib.hashRemoveSigner(
				holder,
				subaccount,
				signer,
				deadline
			);

			if (!isValidSig(holder, _hashTypedData(subaccountHash), signature))
				revert InvalidSignature();
		}

		signers[holder][subaccount][signer] = false;
		emit RemoveSigner(holder, subaccount, signer);
	}

	function getSwapData(
		Swap calldata swap,
		uint256 previousFill,
		uint256 newFill
	) internal pure returns (
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
			Swap calldata swap = swaps[i].swap;

			address holder = swap.holder;

			UserData storage userState = userData[swap.holder][msg.sender][swap.delay];
			UserData storage toState = userData[swap.to][msg.sender][swap.delay];
			// note: allow for swaps between balances with different delays

			if (block.timestamp > (swap.deadlineAndNonce >> 128))
				revert OrderExpired();

			bytes32 swapHash = TypedDataHashLib.hashSwap(
				swap.holder,
				swap.holderSubaccount,
				swap.to,
				swap.toSubaccount,
				msg.sender,
				swap.delay,
				swap.deadlineAndNonce,
				swap.inputs,
				swap.outputs
			);

			// Note: The computed digest serves as the order identifier (orderId) for this swap.
			bytes32 digest = _hashTypedData(swapHash);

			uint256 previousFill = fill[holder][digest];

			if (previousFill == 0) {
				// change holder -> signer from Swap
				// todo: add signer field to Swap and check whether signer has access to subaccount
				if (!isValidSig(holder, digest, signatures[i]))
					revert InvalidSignature();
			} else {
				previousFill--;
			}
			uint256 newFill = previousFill + swaps[i].output; // todo: revert overflow no message
			fill[holder][digest] = newFill + 1;
			emit OrderSwapped(holder, digest, newFill + 1);

			(uint256 inGcd, uint256 outGcd, uint256 amountIn) = getSwapData(
				swap,
				previousFill,
				newFill
			);

			uint256 userSlot = getSlot(userState.balances[swap.holderSubaccount]);
			uint256 toSlot = getSlot(toState.balances[swap.toSubaccount]);
			uint256 operatorSlot = getSlot(operatorState.balances[0]);

			addFlashOps(swap.inputs, operatorSlot, userSlot, inGcd, amountIn);
			addFlashOps(swap.outputs, toSlot, operatorSlot, outGcd, amountIn);
		}

		for (uint256 i = 0; i < swaps.length; i++) {
			Swap calldata swap = swaps[i].swap;
			mapping (uint256 tokenId => uint256 balance) storage userBalances =
				userData[swap.holder][msg.sender][swap.delay].balances[swap.holderSubaccount];
			mapping (uint256 tokenId => uint256 balance) storage toBalances =
				userData[swap.to][msg.sender][swap.delay].balances[swap.toSubaccount];

			settleFlashOps(swap.inputs, userBalances, operatorState.balances[0]);
			settleFlashOps(swap.outputs, toBalances, operatorState.balances[0]);
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
	function getSlot(
		mapping (uint256 tokenId => uint256 balance) storage balances
	) internal view returns (uint256 slot) {
		assembly ("memory-safe") {
			slot := balances.slot
		}
	}

	function settleFlashOp(
		uint256 id,
		mapping (uint256 tokenId => uint256 balance) storage balances
	) internal {
		(uint256 positive, uint256 negative) =
			Flash.readAndNullifyFlashValue(HashLib.hash(id, getSlot(balances)));

		if (positive != 0)
			balances[id] += positive;
		else if (negative != 0)
			balances[id] -= negative;
	}

	function settleFlashOps(
		TokenOp[] calldata array,
		mapping (uint256 tokenId => uint256 balance) storage balances0,
		mapping (uint256 tokenId => uint256 balance) storage balances1
	) internal {
		for (uint256 i = 0; i < array.length; i++) {
			uint256 id = array[i].tokenId;
			settleFlashOp(id, balances0);
			settleFlashOp(id, balances1);
		}
	}
}
