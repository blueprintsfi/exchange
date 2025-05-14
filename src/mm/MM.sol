// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {BasicBlueprint} from "core/blueprints/BasicBlueprint.sol";
import {IBlueprintManager, TokenOp} from "core/interfaces/IBlueprintManager.sol";
import {IMMFactory} from "../interfaces/IMMFactory.sol";

contract MM is BasicBlueprint {
	address immutable public holder;
	address immutable public operator;
	uint256 immutable public delay;
	address immutable public implementation;
	IMMFactory immutable public factory;

	constructor(
		IBlueprintManager _manager,
		address _holder,
		address _operator,
		uint256 _delay,
		address _implementation
	) BasicBlueprint(_manager) {
		holder = _holder;
		operator = _operator;
		delay = _delay;
		implementation = _implementation;
		factory = IMMFactory(msg.sender);
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

		(bool success,) = implementation.delegatecall(action);
		require(success);

		// returndata:
		// 0: subaccount
		// 1: mint pointer (to 0xa0)
		// 2: burn pointer (to 0xa0)
		// 3: give pointer
		// 4: take pointer
		// 5: zero slot
		// 6...: give length and contents
		// later...: take length and contents
		assembly {
			returndatacopy(0, 0, 0x60)
			let arr := mload(0x20)
			returndatacopy(0x20, arr, 0x20)
			let arrLength := mload(0x20)
			let giveByteLength := add(0x20, shl(6, arrLength))
			returndatacopy(0xc0, arr, giveByteLength)
			arr := mload(0x40)
			returndatacopy(0x20, arr, 0x20)
			arrLength := mload(0x20)
			let takeByteLength := add(0x20, shl(6, arrLength))
			let ptr := add(0xc0, giveByteLength)
			returndatacopy(ptr, arr, takeByteLength)
			mstore(0x20, 0xa0)
			mstore(0x40, 0xa0)
			mstore(0x60, 0xc0)
			mstore(0x80, ptr)
			mstore(0xa0, 0)
			return(0, add(ptr, takeByteLength))
		}
	}

	function withdraw(uint256 subaccount, TokenOp[] calldata ops) external {
		require(msg.sender == holder);
		uint256 ts = factory.ragequitTimestamp(address(this));
		require(ts != 0);
		require(ts + delay >= block.timestamp);
		manager.tryFlashTransferFrom(address(this), subaccount, msg.sender, 0, ops);
	}

	function allowActions(uint256 count) external {
		require(msg.sender == operator);
		assembly ("memory-safe") {
			tstore(0, count)
		}
	}
}
