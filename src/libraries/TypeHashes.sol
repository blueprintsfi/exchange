// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

bytes32 constant WITHDRAW_TYPEHASH = keccak256(
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

bytes32 constant SWAP_TYPEHASH = keccak256(
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

bytes32 constant ADD_SIGNER_TYPEHASH = keccak256(
	"AddSigner("
		"address holder,"
		"uint256 subaccount,"
		"address signer,"
		"uint256 deadline"
	")"
);

bytes32 constant REMOVE_SIGNER_TYPEHASH = keccak256(
	"RemoveSigner("
		"address holder,"
		"uint256 subaccount,"
		"address signer,"
		"uint256 deadline"
	")"
);
