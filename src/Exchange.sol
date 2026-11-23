// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {HashLib} from "core/libraries/HashLib.sol";
import {IBlueprintManager, TokenOp} from "core/interfaces/IBlueprintManager.sol";
import {hashOrder, hashSetDelegatedSigner} from "./libraries/ExchangeHashing.sol";
import {IExchange, OrderExecution, Account, SequencerTransfer, Label} from "./interfaces/IExchange.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {FixedPointMathLib as Math} from "solady/utils/FixedPointMathLib.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

function isValidSig(address signer, bytes32 hash, bytes calldata signature) view returns (bool) {
	return SignatureCheckerLib.isValidSignatureNowCalldata(signer, hash, signature);
}

contract Exchange is IExchange, EIP712 {
	IBlueprintManager public immutable manager;
	mapping (address holder => mapping (address sequencer => uint256 timestamp)) public ragequitTime;
	mapping (address holder =>
		mapping (Label label =>
			mapping (address delegatedSigner => uint256 revokedAt))) public delegatedSigners;
	mapping (uint256 subaccount => mapping (bytes32 orderId => uint256 filled)) public fill;

	constructor(IBlueprintManager _manager) EIP712() {
		manager = _manager;
	}

	function _domainNameAndVersion() internal pure override returns (
		string memory name,
		string memory version
	) {
		name = "Exchange";
		version = "1";
	}

	function getSubaccount(
		address holder,
		Label label,
		address sequencer,
		uint256 delay
	) public pure returns (uint256 subaccount) {
		subaccount = HashLib.hash(holder, Label.unwrap(label));
		subaccount = HashLib.hash(sequencer, subaccount);
		subaccount = HashLib.hash(delay, subaccount);
	}

	function getSubaccount(Account calldata account) public pure returns (uint256 subaccount) {
		return getSubaccount(account.holder, account.label, account.sequencer, account.delay);
	}

	function getBalance(
		address holder,
		Label label,
		address sequencer,
		uint256 delay,
		uint256 tokenId
	) external view returns (uint256 balance) {
		uint256 subaccount = getSubaccount(holder, label, sequencer, delay);
		balance = manager.balanceOf(address(this), subaccount, tokenId);
	}

	function hasAccess(
		address signerOrSender,
		address holder,
		Label label,
		uint256 delay
	) public view returns (bool) {
		if (signerOrSender == holder)
			return true;
		if (Label.unwrap(label) != 0) {
			uint256 _revokedAt = delegatedSigners[holder][label][signerOrSender];
			if (_revokedAt == 1)
				return true;
			if (_revokedAt != 0 && _revokedAt + delay > block.timestamp)
				return true;
		}
		uint256 revokedAt = delegatedSigners[holder][Label.wrap(0)][signerOrSender];
		if (revokedAt == 1)
			return true;
		return revokedAt != 0 && revokedAt + delay > block.timestamp;
	}

	function isSequencerOrRagequitted(Account calldata account) internal view returns (bool) {
		if (msg.sender == account.sequencer)
			return true;
		if (!hasAccess(msg.sender, account.holder, account.label, 0))
			return false;
		uint256 ts = ragequitTime[account.holder][account.sequencer];
		return ts != 0 && ts + account.delay <= block.timestamp;
	}

	function ragequit(address holder, address sequencer) external {
		if (!hasAccess(msg.sender, holder, Label.wrap(0), 0))
			revert Unauthorized();
		if (ragequitTime[holder][sequencer] != 0)
			revert RagequitAlreadySet();
		ragequitTime[holder][sequencer] = block.timestamp;
		emit Ragequit(holder, sequencer, msg.sender, block.timestamp);
	}

	function unragequit(address holder, address sequencer) external {
		if (!hasAccess(msg.sender, holder, Label.wrap(0), 0))
			revert Unauthorized();
		if (ragequitTime[holder][sequencer] == 0)
			revert NoRagequitSet();
		ragequitTime[holder][sequencer] = 0;
		emit Unragequit(holder, sequencer, msg.sender);
	}

	function withdraw(Account calldata account, TokenOp[] calldata withdrawals) external {
		if (!isSequencerOrRagequitted(account))
			revert Unauthorized();

		manager.transferFrom(address(this), getSubaccount(account), account.holder, 0, withdrawals);
		emit Withdraw(account.holder, account.label, account.sequencer, account.delay, withdrawals);
	}

	function cancel(Account calldata account, bytes32[] calldata orderIds) external {
		if (!isSequencerOrRagequitted(account))
			revert Unauthorized();

		uint256 subaccount = getSubaccount(account);
		for (uint256 i = 0; i < orderIds.length; i++)
			fill[subaccount][orderIds[i]] = type(uint256).max;
		emit OrdersCanceled(account.holder, orderIds);
	}

	function setDelegatedSigner(
		address holder,
		Label label,
		address delegatedSigner,
		uint256 deadline,
		bool isActive,
		bytes calldata signature
	) external {
		if (!hasAccess(msg.sender, holder, Label.wrap(0), 0)) {
			if (block.timestamp > deadline)
				revert DeadlinePassed();

			bytes32 setDelegatedSignerHash = hashSetDelegatedSigner(holder, label, delegatedSigner, deadline, isActive);
			if (!isValidSig(holder, _hashTypedData(setDelegatedSignerHash), signature))
				revert InvalidSignature();
		}

		if (isActive) {
			delegatedSigners[holder][label][delegatedSigner] = 1;
		} else {
			if (delegatedSigners[holder][label][delegatedSigner] != 1)
				revert NotDelegatedSigner();
			delegatedSigners[holder][label][delegatedSigner] = block.timestamp;
		}

		emit DelegatedSignerSet(holder, label, delegatedSigner, isActive);
	}

	function executeOrders(OrderExecution[] calldata orders) external {
		uint256 sequencerSubaccount = getSubaccount(msg.sender, Label.wrap(0), msg.sender, 0);
		for (uint256 i = 0; i < orders.length; i++) {
			OrderExecution calldata order = orders[i];
			address holder = order.holder;
			uint256 accountSubaccount = getSubaccount(holder, order.label, msg.sender, order.delay);

			if (block.timestamp > (order.deadlineAndNonce >> 128))
				revert OrderExpired();

			bytes32 orderId = hashOrder(msg.sender, order);
			uint256 previousFill = fill[accountSubaccount][orderId];
			if (previousFill == 0) {
				address signer = order.signer;
				if (!hasAccess(signer, holder, order.label, order.delay))
					revert InvalidSigner();
				if (!isValidSig(signer, _hashTypedData(orderId), order.signature))
					revert InvalidSignature();
			} else {
				unchecked {previousFill--;}
			}
			uint256 denominator = order.fillDenominator;
			uint256 newFill;
			unchecked {
				newFill = previousFill + order.fillIncrease;
				if (newFill < previousFill || newFill > denominator)
					revert OrderOverfill();
				if (denominator + 1 < 2) // revert if fillDenominator is 0 or type(uint).max
					revert InvalidFillDenominator();
				fill[accountSubaccount][orderId] = newFill + 1;
			}
			emit OrderFilled(holder, orderId, newFill);

			TokenOp[] memory outputs = new TokenOp[](order.outputs.length);
			for (uint256 j = 0; j < outputs.length; j++) {
				uint256 amount = order.outputs[j].amount;
				outputs[j] = TokenOp({
					tokenId: order.outputs[j].tokenId,
					amount: Math.fullMulDiv(amount, newFill, denominator)
						- Math.fullMulDiv(amount, previousFill, denominator)
				});
			}
			manager.flashTransferFrom(address(this), sequencerSubaccount, order.to, order.toSubaccount, outputs);

			TokenOp[] memory inputs = new TokenOp[](order.inputs.length);
			// flip fills to easily round up – they are now amounts remaining
			newFill = denominator - newFill;
			previousFill = denominator - previousFill;
			for (uint256 j = 0; j < inputs.length; j++) {
				uint256 amount = order.inputs[j].amount;
				inputs[j] = TokenOp({
					tokenId: order.inputs[j].tokenId,
					// amount remaining before minus amount remaining after the fill
					amount: Math.fullMulDiv(amount, previousFill, denominator)
						- Math.fullMulDiv(amount, newFill, denominator)
				});
			}
			manager.flashTransferFrom(address(this), accountSubaccount, address(this), sequencerSubaccount, inputs);
		}
	}

	function sequencerFlashTransfer(SequencerTransfer[] calldata transfers) external {
		uint256 sequencerSubaccount = getSubaccount(msg.sender, Label.wrap(0), msg.sender, 0);
		for (uint256 i = 0; i < transfers.length; i++) {
			uint256 to = transfers[i].toSubaccount;
			TokenOp[] calldata ops = transfers[i].amounts;
			manager.flashTransferFrom(address(this), sequencerSubaccount, address(this), to, ops);
		}
	}
}
