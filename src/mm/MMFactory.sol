// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MM, IBlueprintManager} from "./MM.sol";
import {IMMFactory} from "../interfaces/IMMFactory.sol";

contract MMFactory is IMMFactory {
	IBlueprintManager immutable public manager;
	mapping (address mm => uint256 timestamp) public ragequitTimestamp;

	event Ragequit(address indexed mm, uint256 timestamp, bool status);

	constructor(IBlueprintManager _manager) {
		manager = _manager;
	}

	function deployMM(
		address holder,
		address operator,
		uint256 delay,
		address implementation
	) public returns (address) {
		return address(new MM(manager, holder, operator, delay, implementation));
	}

	function ragequit(address mm, bool status) external {
		require(msg.sender == MM(mm).holder());
		if (status)
			ragequitTimestamp[mm] = block.timestamp;
		else
			ragequitTimestamp[mm] = 0;

		emit Ragequit(mm, block.timestamp, status);
	}
}
