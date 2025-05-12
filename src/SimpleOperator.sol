// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BasicBlueprint} from "core/blueprints/BasicBlueprint.sol";
import {IBlueprintManager, TokenOp, BlueprintCall} from "core/interfaces/IBlueprintManager.sol";
import {Exchange} from "./Exchange.sol";

contract SimpleOperator is BasicBlueprint {
	address immutable controller;

	constructor(IBlueprintManager manager, address _controller) BasicBlueprint(manager) {
		controller = _controller;
	}

	function executeCalls(address realizer, BlueprintCall[] calldata calls) external {
		require(msg.sender == controller);
		for (uint256 i = 0; i < calls.length; i++) {
			if (calls[i].blueprint != address(this))
				continue;

			bytes calldata action = calls[i].action;
			assembly ("memory-safe") {
				let ptr := mload(0x40)
				calldatacopy(ptr, action.offset, action.length)
				tstore(keccak256(ptr, action.length), 1)
			}
		}

		blueprintManager.cook(realizer, calls);
	}

	function executeAction(bytes calldata action) external onlyManager returns (
		uint256,
		TokenOp[] memory /*mint*/,
		TokenOp[] memory /*burn*/,
		TokenOp[] memory /*give*/,
		TokenOp[] memory /*take*/
	) {
		bool allowed;
		assembly ("memory-safe") {
			let ptr := mload(0x40)
			calldatacopy(ptr, action.offset, action.length)
			let opHash := keccak256(ptr, action.length)
			allowed := tload(opHash)
			tstore(opHash, 0)
		}
		require(allowed);

		(bool success,) = address(bytes20(action)).call(action[20:]);
		require(success);
		return (0, zero(), zero(), zero(), zero());
	}
}
