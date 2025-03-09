// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

library TypeHashes {
	bytes32 public constant TOKENOP_TYPEHASH = keccak256(
		"TokenOp("
			"uint256 tokenId,"
			"uint256 amount"
		")"
	);

	bytes32 public constant WITHDRAW_TYPEHASH = keccak256(
		"Withdraw("
			"address holder,"
			"uint256 subaccount,"
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
			"uint256 holderSubaccount,"
			"address to,"
			"uint256 toSubaccount,"
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

	bytes32 public constant ADD_SIGNER_TYPEHASH = keccak256(
		"AddSigner("
			"address holder,"
			"uint256 subaccount,"
			"address signer,"
			"uint256 deadline"
		")"
	);

	bytes32 public constant REMOVE_SIGNER_TYPEHASH = keccak256(
		"RemoveSigner("
			"address holder,"
			"uint256 subaccount,"
			"address signer,"
			"uint256 deadline"
		")"
	);

	bytes32 public constant SUBACCOUNT_TYPEHASH = keccak256(
		"SubaccountDeclaration("
			"address holder,"
			"address subaccount"
		")"
	);
}
