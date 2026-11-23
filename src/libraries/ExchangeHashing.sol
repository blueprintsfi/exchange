// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {OrderExecution, TokenOp, Label} from "../interfaces/IExchange.sol";

bytes32 constant TOKENOP_TYPEHASH = keccak256(
	"TokenOp("
		"uint256 tokenId,"
		"uint256 amount"
	")"
);

bytes32 constant ORDER_TYPEHASH = keccak256(
	"Order("
		"address holder,"
		"uint256 label,"
		"address sequencer,"
		"uint256 delay,"
		"address to,"
		"uint256 toSubaccount,"
		"uint256 deadlineAndNonce,"
		"uint256 fillDenominator,"
		"bytes32 auxData,"
		"TokenOp[] inputs,"
		"TokenOp[] outputs"
	")"
	"TokenOp("
		"uint256 tokenId,"
		"uint256 amount"
	")"
);

bytes32 constant SET_DELEGATED_SIGNER_TYPEHASH = keccak256(
	"SetDelegatedSigner("
		"address holder,"
		"uint256 label,"
		"address delegatedSigner,"
		"uint256 deadline,"
		"bool isActive"
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

function hashOrder(address sequencer, OrderExecution calldata order) pure returns (bytes32 result) {
	bytes32 inputsHash = hashTokenOps(order.inputs);
	bytes32 outputsHash = hashTokenOps(order.outputs);
	bytes32 typehash = ORDER_TYPEHASH;

	assembly ("memory-safe") {
		let ptr := mload(0x40)
		mstore(ptr, typehash)
		mstore(add(ptr, 0x20), and(calldataload(order), ADDRESS_MASK)) // holder
		mstore(add(ptr, 0x40), calldataload(add(order, 0x20))) // label
		mstore(add(ptr, 0x60), and(sequencer, ADDRESS_MASK))
		mstore(add(ptr, 0x80), calldataload(add(order, 0x40))) // delay
		mstore(add(ptr, 0xa0), and(calldataload(add(order, 0x60)), ADDRESS_MASK)) // to
		// mstore(add(ptr, 0xc0), calldataload(add(order, 0x80))) // toSubaccount
		// mstore(add(ptr, 0xe0), calldataload(add(order, 0xa0))) // deadlineAndNonce
		// mstore(add(ptr, 0x100), calldataload(add(order, 0xc0))) // fillDenominator
		// mstore(add(ptr, 0x120), calldataload(add(order, 0xe0))) // auxData
		// the above lines are expressed as:
		calldatacopy(add(ptr, 0xc0), add(order, 0x80), 0x80)
		mstore(add(ptr, 0x140), inputsHash)
		mstore(add(ptr, 0x160), outputsHash)
		result := keccak256(ptr, 0x180)
	}
}

function hashSetDelegatedSigner(
	address holder,
	Label label,
	address delegatedSigner,
	uint256 deadline,
	bool isActive
) pure returns (bytes32 result) {
	bytes32 typehash = SET_DELEGATED_SIGNER_TYPEHASH;

	assembly ("memory-safe") {
		let ptr := mload(0x40)
		mstore(ptr, typehash)
		mstore(add(ptr, 0x20), and(holder, ADDRESS_MASK))
		mstore(add(ptr, 0x40), label)
		mstore(add(ptr, 0x60), and(delegatedSigner, ADDRESS_MASK))
		mstore(add(ptr, 0x80), deadline)
		mstore(add(ptr, 0xa0), iszero(iszero(isActive)))
		result := keccak256(ptr, 0xc0)
	}
}
