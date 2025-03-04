// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TokenOp} from "../../lib/core/src/blueprints/BasicBlueprint.sol";

/// @title TypeHashes
/// @notice Contains EIP-712 type hashes used in the Exchange contract
contract TypeHashes {
	bytes32 public constant WITHDRAW_TYPEHASH = keccak256(
		"Withdraw("
			"address holder,"
			"uint256 delay,"
			"uint256 nonce,"
			"TokenOp[] withdrawals"
		")"
		"TokenOp("
			"uint256 tokenId,"
			"uint256 amount"
		")"
	);

	bytes32 public constant SWAP_TYPEHASH = keccak256(
		"Swap("
			"address holder,"
			"address to,"
			"address operator,"
			"uint256 delay,"
			"uint256 deadlineAndNonce,"
			"TokenOp[] inputs,"
			"TokenOp[] outputs"
		")"
		"TokenOp("
			"uint256 tokenId,"
			"uint256 amount"
		")"
	);

	bytes32 public constant SUBACCOUNT_TYPEHASH = keccak256(
		"SubaccountDeclaration("
			"address holder,"
			"address subaccount"
		")"
	);
}
