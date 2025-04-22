// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SwapExecution, BalanceInfo, TokenOp} from "../interfaces/IExchange.sol";

bytes32 constant TOKENOP_TYPEHASH = keccak256(
	"TokenOp("
		"uint256 tokenId,"
		"uint256 amount"
	")"
);

bytes32 constant WITHDRAW_TYPEHASH = keccak256(
	"Withdraw("
		"address holder,"
		"uint256 subaccount,"
		"address operator,"
		"uint256 delay,"
		"uint256 nonce,"
		"TokenOp[] withdrawals"
	")"
	"TokenOp("
		"uint256 tokenId,"
		"uint256 amount"
	")"
);

bytes32 constant SWAP_TYPEHASH = keccak256(
	"Swap("
		"address holder,"
		"uint256 holderSubaccount,"
		"address operator,"
		"uint256 delay,"
		"address to,"
		"uint256 toSubaccount,"
		"uint256 deadlineAndNonce,"
		"uint256 fillDenominator,"
		"TokenOp[] inputs,"
		"TokenOp[] outputs"
	")"
	"TokenOp("
		"uint256 tokenId,"
		"uint256 amount"
	")"
);

bytes32 constant SET_SIGNER_TYPEHASH = keccak256(
	"SetSigner("
		"address holder,"
		"uint256 subaccount,"
		"address signer,"
		"uint256 deadline,"
		"bool isSigner"
	")"
);

uint256 constant ADDRESS_MASK = 0x00ffffffffffffffffffffffffffffffffffffffff;

function hashTokenOps(TokenOp[] calldata ops) pure returns (bytes32 result) {
	bytes32 typehash = TOKENOP_TYPEHASH;

	assembly ("memory-safe") {
		let ptr := mload(0x40)
		let hashLen := shl(5, ops.length)
		let hashptr := add(ptr, hashLen)
		mstore(hashptr, typehash)
		let hashdataptr := add(hashptr, 0x20)
		let nextHashPtr := ptr

		for {} lt(nextHashPtr, hashptr) {nextHashPtr := add(nextHashPtr, 0x20)} {
			calldatacopy(hashdataptr, ops.offset, 0x40)
			mstore(nextHashPtr, keccak256(hashptr, 0x60))
			ops.offset := add(ops.offset, 0x40)
		}

		result := keccak256(ptr, hashLen)
	}
}

function hashWithdrawal(
	BalanceInfo calldata info,
	uint256 nonce,
	TokenOp[] calldata withdrawals
) pure returns (bytes32 result) {
	bytes32 withdrawalsHash = hashTokenOps(withdrawals);
	bytes32 typehash = WITHDRAW_TYPEHASH;

	assembly ("memory-safe") {
		let ptr := mload(0x40)
		mstore(ptr, typehash)
		mstore(add(ptr, 0x20), and(calldataload(info), ADDRESS_MASK))
		mstore(add(ptr, 0x40), calldataload(add(info, 0x20)))
		mstore(add(ptr, 0x60), and(calldataload(add(info, 0x40)), ADDRESS_MASK))
		mstore(add(ptr, 0x80), calldataload(add(info, 0x60)))
		mstore(add(ptr, 0xa0), nonce)
		mstore(add(ptr, 0xc0), withdrawalsHash)
		result := keccak256(ptr, 0xe0)
	}
}

function hashSwap(address operator, SwapExecution calldata swap) pure returns (bytes32 result) {
	bytes32 inputsHash = hashTokenOps(swap.inputs);
	bytes32 outputsHash = hashTokenOps(swap.outputs);
	bytes32 typehash = SWAP_TYPEHASH;

	assembly ("memory-safe") {
		let ptr := mload(0x40)
		mstore(ptr, typehash)
		mstore(add(ptr, 0x20), and(calldataload(swap), ADDRESS_MASK)) // holder
		mstore(add(ptr, 0x40), calldataload(add(swap, 0x20))) // holderSubaccount
		mstore(add(ptr, 0x60), and(operator, ADDRESS_MASK))
		mstore(add(ptr, 0x80), calldataload(add(swap, 0x40))) // delay
		mstore(add(ptr, 0xa0), and(calldataload(add(swap, 0x60)), ADDRESS_MASK)) // to
		// mstore(add(ptr, 0xc0), calldataload(add(swap, 0x80))) // toSubaccount
		// mstore(add(ptr, 0xe0), calldataload(add(swap, 0xa0))) // deadlineAndNonce
		// mstore(add(ptr, 0x100), calldataload(add(swap, 0xc0))) // fillDenominator
		calldatacopy(add(ptr, 0xc0), add(swap, 0x80), 0x60)
		mstore(add(ptr, 0x120), inputsHash)
		mstore(add(ptr, 0x140), outputsHash)
		result := keccak256(ptr, 0x160)
	}
}

function hashSetSigner(
	address holder,
	uint256 subaccount,
	address signer,
	uint256 deadline,
	bool isSigner
) pure returns (bytes32 result) {
	bytes32 typehash = SET_SIGNER_TYPEHASH;

	assembly ("memory-safe") {
		let ptr := mload(0x40)
		mstore(ptr, typehash)
		mstore(add(ptr, 0x20), and(holder, ADDRESS_MASK))
		mstore(add(ptr, 0x40), subaccount)
		mstore(add(ptr, 0x60), and(signer, ADDRESS_MASK))
		mstore(add(ptr, 0x80), deadline)
		mstore(add(ptr, 0xa0), iszero(iszero(isSigner)))
		result := keccak256(ptr, 0xc0)
	}
}
