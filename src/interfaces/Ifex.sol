// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TokenOp} from "core/interfaces/IBlueprintManager.sol";


struct Swap {
	address holder;
	address operator;
	uint256 delay;
	uint256 deadlineAndNonce;
	address to;
	TokenOp[] inputs;
	TokenOp[] outputs;
}

struct SwapExecution {
	Swap swap;
	uint256 output;
}

struct UserData {
	mapping (uint256 tokenId => uint256 balance) balances;
	uint256 nonce;
	uint256 ragequitTime;
}

/// @title Interface for fExchange
/// @notice Contains all errors and events for the fExchange contract
interface IfExchange  {
    /// @notice Thrown when an unauthorized account tries to act on behalf of a holder
    error Unauthorized();

    /// @notice Thrown when a ragequit is already set
    error RagequitAlreadySet();

    /// @notice Thrown when no ragequit is set
    error NoRagequitSet();

    /// @notice Thrown when trying to withdraw before delay has passed
    error DelayNotPassed();

    /// @notice Thrown when trying to fill beyond the maximum amount
    error ExceedsMaxFill();

    /// @notice Thrown when trying to sign an already signed order
    error OrderAlreadySigned();
    
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

    /// @notice Thrown when trying to fill beyond output GCD
    error ExceedsOutputGcd();

    /// @notice Thrown when signature verification fails
    error InvalidSignature();

    /// @notice Thrown when the nonce provided is invalid
    error InvalidNonce();

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
    /// @param delay The delay period
    /// @param sender The address that initiated the ragequit
    /// @param timestamp When the ragequit was initiated
    event Ragequit(
        address indexed holder,
        address indexed operator,
        uint256 indexed delay,
        address sender,
        uint256 timestamp
    );

    /// @notice Emitted when a user cancels their ragequit
    /// @param holder The address canceling ragequit
    /// @param operator The operator address
    /// @param delay The delay period
    /// @param sender The address that canceled the ragequit
    event Unragequit(
        address indexed holder,
        address indexed operator,
        uint256 indexed delay,
        address sender
    );

    /// @notice Emitted when an order is signed
    /// @param holder The address signing the order
    /// @param orderId The unique identifier of the order
    /// @param fill The fill amount (always 1 for signing)
    event OrderSigned(
        address indexed holder,
        bytes32 indexed orderId,
        uint256 fill
    );

    /// @notice Emitted when an order is canceled
    /// @param holder The address that owns the order
    /// @param orderId The unique identifier of the order
    /// @param fill The fill amount (always type(uint256).max for cancellation)
    event OrderCanceled(
        address indexed holder,
        bytes32 indexed orderId,
        uint256 fill
    );

    /// @notice Emitted when an order is canceled by the operator
    /// @param holder The address that owns the order
    /// @param orderId The unique identifier of the order
    /// @param operator The operator that canceled the order
    /// @param fill The fill amount (always type(uint256).max for cancellation)
    event OrderOperatorCanceled(
        address indexed holder,
        bytes32 indexed orderId,
        address indexed operator,
        uint256 fill
    );

    /// @notice Emitted when an order is filled via swap
    /// @param holder The address that owns the order
    /// @param orderId The unique identifier of the order
    /// @param fill The new fill amount
    event OrderSwapped(
        address indexed holder,
        bytes32 indexed orderId,
        uint256 fill
    );
} 