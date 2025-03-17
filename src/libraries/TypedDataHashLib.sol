// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TokenOp} from "../../lib/core/src/interfaces/IBlueprintManager.sol";
import "./TypeHashes.sol";

library TypedDataHashLib {
	// type(uint160).max
	uint256 public constant ADDRESS_MASK = 0x00ffffffffffffffffffffffffffffffffffffffff;

	function hashTokenOps(TokenOp[] calldata ops) public pure returns (bytes32 result) {
		bytes32 typeHash = TOKENOP_TYPEHASH;

		assembly ("memory-safe") {
			let ptr := mload(0x40)
			let hashLen := shl(5, ops.length)
			let hashptr := add(ptr, hashLen)
			mstore(hashptr, typeHash)
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

	function hashWithdraw(
		address holder,
		uint256 subaccount,
		uint256 delay,
		uint256 nonce,
		TokenOp[] calldata withdrawals
	) public pure returns (bytes32 result) {
		bytes32 withdrawalsHash = hashTokenOps(withdrawals);
		bytes32 typeHash = WITHDRAW_TYPEHASH;

		assembly ("memory-safe") {
			let ptr := mload(0x40)
			mstore(ptr, typeHash)
			mstore(add(ptr, 0x20), and(holder, ADDRESS_MASK))
			mstore(add(ptr, 0x40), subaccount)
			mstore(add(ptr, 0x60), delay)
			mstore(add(ptr, 0x80), nonce)
			mstore(add(ptr, 0xa0), withdrawalsHash)
			result := keccak256(ptr, 0xc0)
		}
	}

	function hashSwap(
		address holder,
		uint256 holderSubaccount,
		address to,
		uint256 toSubaccount,
		address operator,
		uint256 delay,
		uint256 deadlineAndNonce,
		TokenOp[] calldata inputs,
		TokenOp[] calldata outputs
	) public pure returns (bytes32 result) {
		bytes32 inputsHash = hashTokenOps(inputs);
		bytes32 outputsHash = hashTokenOps(outputs);
		bytes32 typeHash = SWAP_TYPEHASH;

		assembly ("memory-safe") {
			let ptr := mload(0x40)
			mstore(ptr, typeHash)
			mstore(add(ptr, 0x20), and(holder, ADDRESS_MASK))
			mstore(add(ptr, 0x40), holderSubaccount)
			mstore(add(ptr, 0x60), and(to, ADDRESS_MASK))
			mstore(add(ptr, 0x80), toSubaccount)
			mstore(add(ptr, 0xa0), and(operator, ADDRESS_MASK))
			mstore(add(ptr, 0xc0), delay)
			mstore(add(ptr, 0xe0), deadlineAndNonce)
			mstore(add(ptr, 0x100), inputsHash)
			mstore(add(ptr, 0x120), outputsHash)
			result := keccak256(ptr, 0x140)
		}
	}

	function hashAddSigner(
		address holder,
		uint256 subaccount,
		address signer,
		uint256 deadline
	) public pure returns (bytes32 result) {
		bytes32 typeHash = ADD_SIGNER_TYPEHASH;

		assembly ("memory-safe") {
			let ptr := mload(0x40)
			mstore(ptr, typeHash)
			mstore(add(ptr, 0x20), and(holder, ADDRESS_MASK))
			mstore(add(ptr, 0x40), subaccount)
			mstore(add(ptr, 0x60), and(signer, ADDRESS_MASK))
			mstore(add(ptr, 0x80), deadline)
			result := keccak256(ptr, 0xa0)
		}
	}

	function hashRemoveSigner(
		address holder,
		uint256 subaccount,
		address signer,
		uint256 deadline
	) public pure returns (bytes32 result) {
		bytes32 typeHash = REMOVE_SIGNER_TYPEHASH;

		assembly ("memory-safe") {
			let ptr := mload(0x40)
			mstore(ptr, typeHash)
			mstore(add(ptr, 0x20), and(holder, ADDRESS_MASK))
			mstore(add(ptr, 0x40), subaccount)
			mstore(add(ptr, 0x60), and(signer, ADDRESS_MASK))
			mstore(add(ptr, 0x80), deadline)
			result := keccak256(ptr, 0xa0)
		}
	}
}

