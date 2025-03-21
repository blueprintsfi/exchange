// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BasicBlueprint} from "core/blueprints/BasicBlueprint.sol";
import {IBlueprintManager, TokenOp, BlueprintCall} from "core/interfaces/IBlueprintManager.sol";
import {Exchange} from "./Exchange.sol";

contract SimpleOperator is BasicBlueprint {
	address immutable controller;

	constructor(
		IBlueprintManager _blueprintManager,
		address _controller
	) BasicBlueprint(_blueprintManager) {
		controller = _controller;
	}

	function executeCalls(
		bytes32[] calldata opHashes,
		address realizer,
		BlueprintCall[] calldata calls
	) external {
		require(msg.sender == controller);
		for (uint256 i = 0; i < opHashes.length; i++) {
			bytes32 opHash = opHashes[i];
			assembly {
				tstore(opHash, 1)
			}
		}

		blueprintManager.cook(realizer, calls);
	}

	// deposit using cook
	function executeAction(bytes calldata action) external onlyManager returns (
		TokenOp[] memory /*mint*/,
		TokenOp[] memory /*burn*/,
		TokenOp[] memory /*give*/,
		TokenOp[] memory /*take*/
	) {
		bytes32 opHash;
		bool allowed;
		assembly {
			let ptr := mload(0x40)
			calldatacopy(ptr, action.offset, action.length)
			opHash := keccak256(ptr, action.length)
			allowed := tload(opHash)
			tstore(opHash, 0)
		}
		require(allowed);

		(address toCall, bytes memory data) = abi.decode(action, (address, bytes));
		(bool success,) = toCall.call(data);
		require(success);
		return (zero(), zero(), zero(), zero());
	}
}
