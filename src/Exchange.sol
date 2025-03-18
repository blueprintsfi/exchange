// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {gcd} from "core/libraries/Math.sol";
import {HashLib} from "core/libraries/HashLib.sol";
import {BasicBlueprint} from "core/blueprints/BasicBlueprint.sol";
import {IBlueprintManager, TokenOp} from "core/interfaces/IBlueprintManager.sol";
import {TypedDataHashLib} from "./libraries/TypedDataHashLib.sol";
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

		blueprintManager.flashTransferFrom(
			address(this),
			0,
			address(this),
			getSubaccount(depositFor, subaccount, operator, delay),
			deposits
		);

		emit Deposit(depositFor, operator, delay, deposits);
		return (zero(), zero(), zero(), deposits);
	}

	function getSubaccount(
		address holder,
		uint256 exchangeSubaccount,
		address operator,
		uint256 delay
	) public pure returns (uint256 subaccount) {
		subaccount = HashLib.hash(holder, exchangeSubaccount);
		subaccount = HashLib.hash(operator, subaccount);
		subaccount = HashLib.hash(delay, subaccount);
	}

	function getBalance(
		address holder,
		uint256 exchangeSubaccount,
		address operator,
		uint256 delay,
		uint256 tokenId
	) external view returns (uint256 balance) {
		balance = blueprintManager.balanceOf(
			address(this),
			getSubaccount(holder, exchangeSubaccount, operator, delay),
			tokenId
		);
	}

	function hasAccess(address sender, address holder, uint256 subaccount) public view returns (bool) {
		if (sender == holder)
			return true;
		if (subaccount != 0) {
			if (signers[holder][subaccount][sender])
				return true;
		}
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

		blueprintManager.transferFrom(
			address(this),
			getSubaccount(holder, subaccount, operator, delay),
			to,
			0,
			withdrawals
		);
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

		blueprintManager.transferFrom(
			address(this),
			getSubaccount(holder, subaccount, operator, delay),
			to,
			0,
			withdrawals
		);
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
		uint256 operatorSubaccount = getSubaccount(msg.sender, 0, msg.sender, 0);
		for (uint256 i = 0; i < swaps.length; i++) {
			Swap calldata swap = swaps[i].swap;
			address holder = swap.holder;
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

			uint256 fromSubaccount = getSubaccount(holder, swap.holderSubaccount, msg.sender, swap.delay);
			uint256 toSubaccount = getSubaccount(swap.to, swap.toSubaccount, msg.sender, swap.delay);

			makeTransfers(swap.inputs, fromSubaccount, operatorSubaccount, inGcd, amountIn);
			makeTransfers(swap.outputs, operatorSubaccount, toSubaccount, outGcd, amountIn);
		}
	}

	function makeTransfers(
		TokenOp[] calldata array,
		uint256 fromSubaccount,
		uint256 toSubaccount,
		uint256 gcd,
		uint256 amountIn
	) internal {
		TokenOp[] memory amounts = array;
		for (uint256 i = 0; i < array.length; i++)
			amounts[i].amount = amounts[i].amount / gcd * amountIn;

		blueprintManager.flashTransferFrom(address(this), fromSubaccount, address(this), toSubaccount, amounts);
	}
}
