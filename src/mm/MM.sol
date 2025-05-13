// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BasicBlueprint} from "core/blueprints/BasicBlueprint.sol";
import {IBlueprintManager, TokenOp} from "core/interfaces/IBlueprintManager.sol";
import {IMarketMakerImplementation} from "../interfaces/IMarketMakerImplementation.sol";

contract MM is BasicBlueprint {
	uint256 public ragequitTimestamp;

	address immutable public holder;
	address immutable public operator;
	uint256 immutable public delay;
	IMarketMakerImplementation immutable public implementation;

	event Ragequit(uint256 timestamp, bool status);

	constructor(
		IBlueprintManager manager,
		address _holder,
		address _operator,
		uint256 _delay,
		address _implementation
	) BasicBlueprint(manager) {
		holder = _holder;
		operator = _operator;
		delay = _delay;
		implementation = IMarketMakerImplementation(_implementation);
	}

	function executeAction(bytes calldata action) external onlyManager returns (
		uint256,
		TokenOp[] memory /*mint*/,
		TokenOp[] memory /*burn*/,
		TokenOp[] memory /*give*/,
		TokenOp[] memory /*take*/
	) {
		uint256 remaining;
		assembly ("memory-safe") {
			remaining := tload(0)
			tstore(0, sub(remaining, 1)) // optimistically decrease permitted actions counter
		}
		if (remaining == 0)
			revert AccessDenied();

		(uint256 subaccount, TokenOp[] memory give, TokenOp[] memory take) =
			implementation.executeAction(action);

		return (subaccount, zero(), zero(), give, take);
	}

	function ragequit(bool status) external {
		require(msg.sender == holder);
		if (status)
			ragequitTimestamp = block.timestamp;
		else
			ragequitTimestamp = 0;

		emit Ragequit(block.timestamp, status);
	}

	function withdraw(uint256 subaccount, TokenOp[] calldata ops) external {
		require(msg.sender == holder);
		require(ragequitTimestamp + delay >= block.timestamp);
		blueprintManager.tryFlashTransferFrom(address(this), subaccount, msg.sender, 0, ops);
	}

	function allowActions(uint256 count) external {
		require(msg.sender == operator);
		assembly ("memory-safe") {
			tstore(0, count)
		}
	}
}
