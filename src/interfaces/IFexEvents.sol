// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TokenOp} from "core/blueprints/BasicBlueprint.sol";

interface IFexEvents {
    /// @notice Emitted when tokens are deposited into the exchange
    /// @param depositFor The address receiving the deposit
    /// @param operator The operator address
    /// @param delay The delay period for the deposit
    /// @param deposits Array of token operations containing deposit details
    event Deposit(address indexed depositFor, address indexed operator, uint256 delay, TokenOp[] deposits);

    /// @notice Emitted when a user initiates ragequit
    /// @param holder The address initiating ragequit
    /// @param operator The operator address
    /// @param delay The delay period
    /// @param timestamp When the ragequit was initiated
    event RageQuit(address indexed holder, address indexed operator, uint256 delay, uint256 timestamp);

    /// @notice Emitted when a user cancels their ragequit
    /// @param holder The address canceling ragequit
    /// @param operator The operator address
    /// @param delay The delay period
    event UnrageQuit(address indexed holder, address indexed operator, uint256 delay);

    /// @notice Emitted when an order is signed
    /// @param holder The address signing the order
    /// @param orderId The unique identifier of the order
    event OrderSigned(address indexed holder, bytes32 indexed orderId);
} 