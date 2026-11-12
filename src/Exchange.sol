// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {HashLib} from "core/libraries/HashLib.sol";
import {IBlueprintManager, TokenOp} from "core/interfaces/IBlueprintManager.sol";
import {hashWithdrawal, hashSwap, hashSetSigner} from "./libraries/ExchangeHashing.sol";
import {IExchange, UserData, SwapExecution, BalanceInfo, SequencerTransfer, ExchangeSubaccount} from "./interfaces/IExchange.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {FixedPointMathLib as Math} from "solady/utils/FixedPointMathLib.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

function isValidSig(address signer, bytes32 hash, bytes calldata signature) view returns (bool) {
	return SignatureCheckerLib.isValidSignatureNowCalldata(signer, hash, signature);
}

contract Exchange is IExchange, EIP712 {
	IBlueprintManager public immutable manager;
	mapping (address holder => mapping (address sequencer => UserData data)) public userData;
	mapping (address holder =>
		mapping (ExchangeSubaccount subaccount =>
			mapping (address signer => uint256 signerInfo))) public signers;
	mapping (uint256 extSubaccount => mapping (bytes32 hash => uint256 filled)) public fill;

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
		ExchangeSubaccount subaccount,
		address sequencer,
		uint256 delay
	) public pure returns (uint256 extSubaccount) {
		extSubaccount = HashLib.hash(holder, ExchangeSubaccount.unwrap(subaccount));
		extSubaccount = HashLib.hash(sequencer, extSubaccount);
		extSubaccount = HashLib.hash(delay, extSubaccount);
	}

	function getSubaccount(BalanceInfo calldata info) public pure returns (uint256 subaccount) {
		return getSubaccount(info.holder, info.subaccount, info.sequencer, info.delay);
	}

	function getBalance(
		address holder,
		ExchangeSubaccount subaccount,
		address sequencer,
		uint256 delay,
		uint256 tokenId
	) external view returns (uint256 balance) {
		uint256 extSubaccount = getSubaccount(holder, subaccount, sequencer, delay);
		balance = manager.balanceOf(address(this), extSubaccount, tokenId);
	}

	function hasAccess(
		address signerOrSender,
		address holder,
		ExchangeSubaccount subaccount,
		uint256 delay
	) public view returns (bool) {
		if (signerOrSender == holder)
			return true;
		if (ExchangeSubaccount.unwrap(subaccount) != 0) {
			uint256 _signerInfo = signers[holder][subaccount][signerOrSender];
			if (_signerInfo == 1)
				return true;
			if (_signerInfo != 0 && _signerInfo + delay > block.timestamp)
				return true;
		}
		uint256 signerInfo = signers[holder][ExchangeSubaccount.wrap(0)][signerOrSender];
		if (signerInfo == 1)
			return true;
		return signerInfo != 0 && signerInfo + delay > block.timestamp;
	}

	function authorizedDelay(BalanceInfo calldata info) internal view returns (bool) {
		if (msg.sender == info.sequencer)
			return true;
		if (!hasAccess(msg.sender, info.holder, info.subaccount, 0))
			return false;
		uint256 ts = userData[info.holder][info.sequencer].ragequitTime;
		return ts != 0 && ts + info.delay <= block.timestamp;
	}

	function ragequit(address holder, address sequencer) external {
		if (!hasAccess(msg.sender, holder, ExchangeSubaccount.wrap(0), 0))
			revert Unauthorized();
		if (userData[holder][sequencer].ragequitTime != 0)
			revert RagequitAlreadySet();
		userData[holder][sequencer].ragequitTime = block.timestamp;
		emit Ragequit(holder, sequencer, msg.sender, block.timestamp);
	}

	function unragequit(address holder, address sequencer) external {
		if (!hasAccess(msg.sender, holder, ExchangeSubaccount.wrap(0), 0))
			revert Unauthorized();
		if (userData[holder][sequencer].ragequitTime == 0)
			revert NoRagequitSet();
		userData[holder][sequencer].ragequitTime = 0;
		emit Unragequit(holder, sequencer, msg.sender);
	}

	function withdraw(
		BalanceInfo calldata info,
		uint256 nonce,
		TokenOp[] calldata withdrawals,
		bytes calldata signature
	) external {
		if (!authorizedDelay(info)) {
			bytes32 withdrawalHash = hashWithdrawal(info, nonce, withdrawals);
			if (!isValidSig(info.sequencer, _hashTypedData(withdrawalHash), signature))
				revert InvalidSignature();
		}

		if (userData[info.holder][info.sequencer].nonce >= nonce)
			revert InvalidNonce();

		userData[info.holder][info.sequencer].nonce = nonce;

		manager.transferFrom(address(this), getSubaccount(info), info.holder, 0, withdrawals);
		emit Withdraw(info.holder, info.subaccount, info.sequencer, info.delay, withdrawals);
	}

	function cancel(BalanceInfo calldata info, bytes32[] calldata orderIds) external {
		if (!authorizedDelay(info))
			revert Unauthorized();

		uint256 extSubaccount = getSubaccount(info);
		for (uint256 i = 0; i < orderIds.length; i++)
			fill[extSubaccount][orderIds[i]] = type(uint256).max;
		emit OrdersCanceled(info.holder, orderIds);
	}

	function signOrders(BalanceInfo calldata info, bytes32[] calldata orderIds) external {
		if (!hasAccess(msg.sender, info.holder, info.subaccount, 0))
			revert Unauthorized();

		uint256 extSubaccount = getSubaccount(info);
		for (uint256 i = 0; i < orderIds.length; i++) {
			if (fill[extSubaccount][orderIds[i]] != 0)
				continue;
			fill[extSubaccount][orderIds[i]] = 1;
		}
		emit OrdersSigned(msg.sender, info.holder, orderIds);
	}

	function setSigner(
		address holder,
		ExchangeSubaccount subaccount,
		address signer,
		uint256 deadline,
		bool isSigner,
		bytes calldata signature
	) external {
		if (!hasAccess(msg.sender, holder, ExchangeSubaccount.wrap(0), 0)) {
			if (block.timestamp > deadline)
				revert DeadlinePassed();

			bytes32 setSignerHash = hashSetSigner(holder, subaccount, signer, deadline, isSigner);
			if (!isValidSig(holder, _hashTypedData(setSignerHash), signature))
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
		uint256 sequencerExtSubaccount = getSubaccount(msg.sender, ExchangeSubaccount.wrap(0), msg.sender, 0);
		for (uint256 i = 0; i < swaps.length; i++) {
			SwapExecution calldata swap = swaps[i];
			address holder = swap.holder;
			uint256 fromExtSubaccount = getSubaccount(holder, swap.subaccount, msg.sender, swap.delay);

			if (block.timestamp > (swap.deadlineAndNonce >> 128))
				revert OrderExpired();

			bytes32 orderId = hashSwap(msg.sender, swap);
			uint256 previousFill = fill[fromExtSubaccount][orderId];
			if (previousFill == 0) {
				address signer = swap.signer;
				if (!hasAccess(signer, holder, swap.subaccount, swap.delay))
					revert InvalidSigner();
				if (!isValidSig(signer, _hashTypedData(orderId), swap.signature))
					revert InvalidSignature();
			} else {
				unchecked {previousFill--;}
			}
			uint256 denominator = swap.fillDenominator;
			uint256 newFill;
			unchecked {
				newFill = previousFill + swap.output;
				if (newFill < previousFill || newFill > denominator)
					revert OrderOverfill();
				if (denominator + 1 < 2) // revert if fillDenominator is 0 or type(uint).max
					revert InvalidFillDenominator();
				fill[fromExtSubaccount][orderId] = newFill + 1;
			}
			emit OrderSwapped(holder, orderId, newFill);

			TokenOp[] memory inputs = new TokenOp[](swap.inputs.length);
			for (uint256 j = 0; j < inputs.length; j++) {
				uint256 amount = swap.inputs[j].amount;
				inputs[j] = TokenOp({
					tokenId: swap.inputs[j].tokenId,
					amount: Math.fullMulDiv(amount, newFill, denominator)
						- Math.fullMulDiv(amount, previousFill, denominator)
				});
			}
			manager.flashTransferFrom(address(this), fromExtSubaccount, address(this), sequencerExtSubaccount, inputs);

			TokenOp[] memory outputs = new TokenOp[](swap.outputs.length);
			// negate fills to easily round up - they are now amounts remaining
			newFill = denominator - newFill;
			previousFill = denominator - previousFill;
			for (uint256 j = 0; j < outputs.length; j++) {
				uint256 amount = swap.outputs[j].amount;
				outputs[j] = TokenOp({
					tokenId: swap.outputs[j].tokenId,
					// amount remaining before minus amount remaining after swap
					amount: Math.fullMulDiv(amount, previousFill, denominator)
						- Math.fullMulDiv(amount, newFill, denominator)
				});
			}
			manager.flashTransferFrom(address(this), sequencerExtSubaccount, swap.to, swap.toSubaccount, outputs);
		}
	}

	function sequencerFlashTransfer(SequencerTransfer[] calldata transfers) external {
		uint256 sequencer = getSubaccount(msg.sender, ExchangeSubaccount.wrap(0), msg.sender, 0);
		for (uint256 i = 0; i < transfers.length; i++) {
			uint256 to = transfers[i].toSubaccount;
			TokenOp[] calldata ops = transfers[i].amounts;
			manager.flashTransferFrom(address(this), sequencer, address(this), to, ops);
		}
	}
}
