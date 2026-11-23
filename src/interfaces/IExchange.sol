// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TokenOp} from "core/interfaces/IBlueprintManager.sol";

type Label is uint256;

// for eip-712 documentation only, not used in code
struct Order {
	address holder;
	Label label;
	address sequencer;
	uint256 delay;
	address to;
	uint256 toSubaccount; // in terms of BlueprintManager's subaccounts
	uint256 deadlineAndNonce;
	uint256 fillDenominator;
	bytes32 auxData;
	TokenOp[] inputs;
	TokenOp[] outputs;
}

struct Account {
	address holder;
	Label label;
	address sequencer;
	uint256 delay;
}

struct OrderExecution {
	address holder;
	Label label;
	// address sequencer; // inferred from the execution context as msg.sender
	uint256 delay;
	address to;
	uint256 toSubaccount;
	uint256 deadlineAndNonce;
	uint256 fillDenominator;
	bytes32 auxData;
	TokenOp[] inputs;
	TokenOp[] outputs;
	// execution details
	uint256 fillIncrease;
	address signer;
	bytes signature;
}

struct SequencerTransfer {
	uint256 toSubaccount;
	TokenOp[] amounts;
}

/// @title Interface for Exchange
/// @notice Contains all errors and events for the Exchange contract
interface IExchange  {
	/// @notice Thrown when an unauthorized account tries to act on behalf of a holder
	error Unauthorized();

	/// @notice Thrown when trying to remove a delegated signer that isn't active (it may have been one)
	error NotDelegatedSigner();

	/// @notice Thrown when trying to fill an order with a signature from a signer that lacks access
	error InvalidSigner();

	/// @notice Thrown when a ragequit is already set
	error RagequitAlreadySet();

	/// @notice Thrown when no ragequit is set
	error NoRagequitSet();

	/// @notice Thrown when an order has expired
	error OrderExpired();

	/// @notice Thrown the fill denominator is too large or zero
	error InvalidFillDenominator();

	/// @notice Thrown when trying to fill the order over its capacity
	error OrderOverfill();

	/// @notice Thrown when signature verification fails
	error InvalidSignature();

	/// @notice Thrown when the delegated signer update with a signature passed the deadline
	error DeadlinePassed();

	/// @notice Emitted when a user initiates ragequit
	/// @param holder The address initiating ragequit
	/// @param sequencer The sequencer address
	/// @param sender The address that initiated the ragequit
	/// @param timestamp When the ragequit was initiated
	event Ragequit(
		address indexed holder,
		address indexed sequencer,
		address sender,
		uint256 timestamp
	);

	/// @notice Emitted when a user cancels their ragequit
	/// @param holder The address canceling ragequit
	/// @param sequencer The sequencer address
	/// @param sender The address that canceled the ragequit
	event Unragequit(
		address indexed holder,
		address indexed sequencer,
		address sender
	);

	/// @notice Emitted when an order is canceled
	/// @param holder The holder of the order's account
	/// @param orderIds Order ids that were canceled
	event OrdersCanceled(
		address indexed holder,
		bytes32[] orderIds
	);

	/// @notice Emitted when an order is filled
	/// @param holder The holder of the order's account
	/// @param orderId The unique identifier of the order
	/// @param fill The new fill
	event OrderFilled(
		address indexed holder,
		bytes32 indexed orderId,
		uint256 fill
	);

	/// @notice Emitted when a withdrawal is performed
	/// @param holder The address withdrawing funds
	/// @param label The account's label
	/// @param sequencer The sequencer address
	/// @param delay The delay period
	/// @param withdrawals Array of token operations being withdrawn
	event Withdraw(
		address indexed holder,
		Label indexed label,
		address indexed sequencer,
		uint256 delay,
		TokenOp[] withdrawals
	);

	/// @notice Emitted when a delegated signer is set for a holder and label
	/// @param holder The address of the account holder
	/// @param label The label the delegated signer applies to
	/// @param delegatedSigner The address being set as a delegated signer
	/// @param isActive Whether the delegated signer was set or revoked
	event DelegatedSignerSet(
		address indexed holder,
		Label indexed label,
		address delegatedSigner,
		bool isActive
	);
}
