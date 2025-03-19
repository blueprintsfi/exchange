// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

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
		"uint256 delay,"
		"address operator,"
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
