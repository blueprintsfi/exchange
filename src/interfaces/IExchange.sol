// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TokenOp} from "core/interfaces/IBlueprintManager.sol";

// note: for eip-712 documentation only, not used in code
struct Swap {
	address holder;
	uint256 holderSubaccount;
	address operator;
	uint256 delay;
	address to;
	uint256 toSubaccount;
	uint256 deadlineAndNonce;
	uint256 fillDenominator;
	TokenOp[] inputs;
	TokenOp[] outputs;
}

struct BalanceInfo {
	address holder;
	uint256 subaccount;
	address operator;
	uint256 delay;
}

struct SwapExecution {
	address holder;
	uint256 holderSubaccount;
	// address operator;
	uint256 delay;
	address to;
	uint256 toSubaccount;
	uint256 deadlineAndNonce;
	uint256 fillDenominator;
	TokenOp[] inputs;
	TokenOp[] outputs;
	uint256 output;
	address signer;
	bytes signature;
}

struct OperatorTransfer {
	uint256 toSubaccount;
	TokenOp[] amounts;
}

struct UserData {
	uint256 nonce;
	uint256 ragequitTime;
}

/// @title Interface for Exchange
/// @notice Contains all errors and events for the Exchange contract
interface IExchange  {
	/// @notice Thrown when an unauthorized account tries to act on behalf of a holder
	error Unauthorized();

	/// @notice Thrown when trying to remove a signer that isn't a signer (it may have been one)
	error NotSigner();

	/// @notice Thrown when trying to fill an order with a signature from a signer that lacks access
	error InvalidSigner();

	/// @notice Thrown when a ragequit is already set
	error RagequitAlreadySet();

	/// @notice Thrown when no ragequit is set
	error NoRagequitSet();

	/// @notice Thrown when trying to withdraw before delay has passed
	error DelayNotPassed();

	/// @notice Thrown when trying to fill beyond the maximum amount
	error ExceedsMaxFill();

	/// @notice Thrown when trying to initialize cancellation for an order with already initialized cancellation
	error OrderCancelAlreadyInitialized();

	/// @notice Thrown when trying to cancel an order without previous initCancel() call
	error OrderCancelNotInitialized();

	/// @notice Thrown when trying to cancel an order that hasn't been marked for cancellation
	error NotMarkedForCancellation();

	/// @notice Thrown when trying to declare a subaccount that already has a master
	error SubaccountAlreadyDeclared();

	/// @notice Thrown when an order has expired
	error OrderExpired();

	/// @notice Thrown when trying to execute a swap with wrong operator
	error WrongOperator();

	/// @notice Thrown the fill denominator is too large or zero
	error InvalidFillDenominator();

	/// @notice Thrown when trying to fill the order over its capacity
	error OrderOverfill();

	/// @notice Thrown when signature verification fails
	error InvalidSignature();

	/// @notice Thrown when the nonce provided is invalid
	error InvalidNonce();

	/// @notice Thrown when the subaccount declaration with a signature passed the deadline
	error DeadlinePassed();

	/// @notice Emitted when tokens are deposited into the exchange
	/// @param depositFor The address receiving the deposit
	/// @param operator The operator address
	/// @param delay The delay period for the deposit
	/// @param deposits Array of token operations containing deposit details
	event Deposit(
		address indexed depositFor,
		address indexed operator,
		uint256 indexed delay,
		TokenOp[] deposits
	);

	/// @notice Emitted when a user initiates ragequit
	/// @param holder The address initiating ragequit
	/// @param operator The operator address
	/// @param sender The address that initiated the ragequit
	/// @param timestamp When the ragequit was initiated
	event Ragequit(
		address indexed holder,
		address indexed operator,
		address sender,
		uint256 timestamp
	);

	/// @notice Emitted when a user cancels their ragequit
	/// @param holder The address canceling ragequit
	/// @param operator The operator address
	/// @param sender The address that canceled the ragequit
	event Unragequit(
		address indexed holder,
		address indexed operator,
		address sender
	);

	/// @notice Emitted when an order is signed
	/// @param signer The account signing the orders
	/// @param holder The address signing the order
	/// @param orderIds Order ids that were signed
	event OrdersSigned(
		address indexed signer,
		address indexed holder,
		bytes32[] orderIds
	);

	/// @notice Emitted when an order is canceled
	/// @param holder The address that owns the order
	/// @param orderIds Order ids that were canceled
	event OrdersCanceled(
		address indexed holder,
		bytes32[] orderIds
	);

	/// @notice Emitted when an order is filled via swap
	/// @param holder The address that owns the order
	/// @param orderId The unique identifier of the order
	/// @param fill The new fill
	event OrderSwapped(
		address indexed holder,
		bytes32 indexed orderId,
		uint256 fill
	);

	/// @notice Emitted when a withdrawal is performed
	/// @param holder The address withdrawing funds
	/// @param subaccount The subaccount identifier
	/// @param operator The operator address
	/// @param delay The delay period
	/// @param withdrawals Array of token operations being withdrawn
	event Withdraw(
		address indexed holder,
		uint256 indexed subaccount,
		address indexed operator,
		uint256 delay,
		TokenOp[] withdrawals
	);

	/// @notice Emitted when a signer is added to a subaccount
	/// @param holder The address of the account holder
	/// @param subaccount The subaccount identifier
	/// @param signer The address being added as a signer
	/// @param isSigner Whethet the signer was set or cancelled
	event SignerSet(
		address indexed holder,
		uint256 indexed subaccount,
		address signer,
		bool isSigner
	);
}
