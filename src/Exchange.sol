// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {gcd} from "core/libraries/Math.sol";
import {HashLib} from "core/libraries/HashLib.sol";
import {BasicBlueprint} from "core/blueprints/BasicBlueprint.sol";
import {IBlueprintManager, TokenOp} from "core/interfaces/IBlueprintManager.sol";
import {TypedDataHashLib} from "./libraries/TypedDataHashLib.sol";
import {IExchange, UserData, SwapExecution, BalanceInfo} from "src/interfaces/IExchange.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

function isValidSig(address signer, bytes32 hash, bytes calldata signature) view returns (bool) {
	return SignatureCheckerLib.isValidSignatureNowCalldata(signer, hash, signature);
}

contract Exchange is BasicBlueprint, IExchange, EIP712 {
	mapping (address holder => mapping (address operator => UserData data)) public userData;
	mapping (address holder =>
		mapping (uint256 subaccount =>
			mapping (address signer => uint256 signerInfo))) public signers;
	mapping (uint256 managerSubaccount => mapping (bytes32 hash => uint256 filled)) public fill;

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

	function getSubaccount(BalanceInfo calldata info) public pure returns (uint256 subaccount) {
		return getSubaccount(info.holder, info.subaccount, info.operator, info.delay);
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

	function delayedHasAccess(
		address signer,
		address holder,
		uint256 subaccount,
		uint256 delay
	) public view returns (bool) {
		if (signer == holder)
			return true;
		if (subaccount != 0) {
			uint256 signerInfo = signers[holder][subaccount][signer];
			if (signerInfo == 1)
				return true;
			if (signerInfo != 0 && signerInfo + delay < block.timestamp)
				return true;
		}
		uint256 signerInfo = signers[holder][subaccount][signer];
		if (signerInfo == 1)
			return true;
		return signerInfo != 0 && signerInfo + delay < block.timestamp;
	}

	function hasAccess(address sender, address holder, uint256 subaccount) public view returns (bool) {
		if (sender == holder)
			return true;
		if (subaccount != 0) {
			if (signers[holder][subaccount][sender] == 1)
				return true;
		}
		return signers[holder][0][sender] == 1;
	}

	function authorizedDelay(BalanceInfo calldata info) internal view returns (bool) {
		if (msg.sender == info.operator)
			return true;
		if (!hasAccess(msg.sender, info.holder, info.subaccount))
			revert AccessDenied();
		uint256 ts = userData[info.holder][info.operator].ragequitTime;
		return ts != 0 && ts + info.delay <= block.timestamp;
	}

	function ragequit(address holder, address operator) external {
		if (!hasAccess(msg.sender, holder, 0))
			revert Unauthorized();
		if (userData[holder][operator].ragequitTime != 0)
			revert RagequitAlreadySet();
		userData[holder][operator].ragequitTime = block.timestamp;
		emit Ragequit(holder, operator, msg.sender, block.timestamp);
	}

	function unragequit(address holder, address operator) external {
		if (!hasAccess(msg.sender, holder, 0))
			revert Unauthorized();
		if (userData[holder][operator].ragequitTime == 0)
			revert NoRagequitSet();
		userData[holder][operator].ragequitTime = 0;
		emit Unragequit(holder, operator, msg.sender);
	}

	function withdraw(
		BalanceInfo calldata info,
		uint256 nonce,
		TokenOp[] calldata withdrawals,
		bytes calldata signature
	) external {
		if (!authorizedDelay(info)) {
			bytes32 withdrawalHash = TypedDataHashLib.hashWithdraw(info, nonce, withdrawals);
			if (!isValidSig(info.operator, _hashTypedData(withdrawalHash), signature))
				revert InvalidSignature();
		}

		if (userData[info.holder][info.operator].nonce >= nonce)
			revert InvalidNonce();

		userData[info.holder][info.operator].nonce = nonce;

		blueprintManager.transferFrom(address(this), getSubaccount(info), info.holder, 0, withdrawals);
		emit Withdraw(info.holder, info.subaccount, info.operator, info.delay, withdrawals);
	}

	function cancel(BalanceInfo calldata info, bytes32[] calldata orderIds) external {
		if (!authorizedDelay(info))
			revert Unauthorized();

		uint256 managerSubaccount = getSubaccount(info);
		for (uint256 i = 0; i < orderIds.length; i++)
			fill[managerSubaccount][orderIds[i]] = type(uint256).max;
		emit OrdersCanceled(info.holder, orderIds);
	}

	function signOrders(BalanceInfo calldata info, bytes32[] calldata orderIds) external {
		if (!hasAccess(msg.sender, info.holder, info.subaccount))
			revert Unauthorized();

		uint256 managerSubaccount = getSubaccount(info);
		for (uint256 i = 0; i < orderIds.length; i++) {
			if (fill[managerSubaccount][orderIds[i]] != 0)
				continue;
			fill[managerSubaccount][orderIds[i]] = 1;
		}
		emit OrdersSigned(msg.sender, info.holder, orderIds);
	}

	function setSigner(
		address holder,
		uint256 subaccount,
		address signer,
		uint256 deadline,
		bool isSigner,
		bytes calldata signature
	) external {
		if (!hasAccess(msg.sender, holder, 0)) {
			if (block.timestamp > deadline)
				revert DeadlinePassed();

			bytes32 subaccountHash = TypedDataHashLib.hashSetSigner(
				holder,
				subaccount,
				signer,
				deadline,
				isSigner
			);

			if (!isValidSig(holder, _hashTypedData(subaccountHash), signature))
				revert InvalidSignature();
		}

		if (isSigner) {
			signers[holder][subaccount][signer] = 1;
		} else {
			if (signers[holder][subaccount][signer] != 1)
				revert NotSigner();
			signers[holder][subaccount][signer] = block.timestamp;
		}

		emit SignerSet(holder, subaccount, signer, isSigner);
	}

	function executeSwaps(SwapExecution[] calldata swaps) external {
		uint256 operatorSubaccount = getSubaccount(msg.sender, 0, msg.sender, 0);
		for (uint256 i = 0; i < swaps.length; i++) {
			SwapExecution calldata swap = swaps[i];
			address holder = swap.holder;
			uint256 fromSubaccount = getSubaccount(holder, swap.holderSubaccount, msg.sender, swap.delay);
			uint256 toSubaccount = getSubaccount(swap.to, swap.toSubaccount, msg.sender, swap.delay);

			if (block.timestamp > (swap.deadlineAndNonce >> 128))
				revert OrderExpired();

			bytes32 orderId = TypedDataHashLib.hashSwap(msg.sender, swap);
			uint256 previousFill = fill[fromSubaccount][orderId];
			if (previousFill == 0) {
				address signer = swap.signer;
				if (!delayedHasAccess(signer, holder, swap.holderSubaccount, swap.delay))
					revert InvalidSigner();
				if (!isValidSig(signer, _hashTypedData(orderId), swaps[i].signature))
					revert InvalidSignature();
			} else {
				previousFill--;
			}
			uint256 newFill = previousFill + swap.output; // todo: revert overflow no message
			fill[fromSubaccount][orderId] = newFill + 1;
			emit OrderSwapped(holder, orderId, newFill + 1);

			makeTransfers(swap.inputs, fromSubaccount, operatorSubaccount, previousFill, newFill, swap.fillDenominator);
			makeTransfers(swap.outputs, operatorSubaccount, toSubaccount, previousFill, newFill, swap.fillDenominator);
		}
	}

	function makeTransfers(
		TokenOp[] memory amounts,
		uint256 fromSubaccount,
		uint256 toSubaccount,
		uint256 previousFill,
		uint256 newFill,
		uint256 fillDenominator
	) internal {
		for (uint256 i = 0; i < amounts.length; i++) {
			uint256 amount = amounts[i].amount;
			unchecked {
				// revert if fill denominator is 0 or uint(-1), or would overflow when multiplied by amount
				if (fillDenominator + 1 < 2 || fillDenominator * amount / fillDenominator != amount)
					revert InvalidFillDenominator();
				amounts[i].amount = amount * newFill / fillDenominator - amount * previousFill / fillDenominator;
			}
		}

		blueprintManager.flashTransferFrom(address(this), fromSubaccount, address(this), toSubaccount, amounts);
	}
}
