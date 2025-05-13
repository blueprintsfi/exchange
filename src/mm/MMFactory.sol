// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {MM, IBlueprintManager} from "./MM.sol";
// import {IBlueprintManager, TokenOp} from "core/interfaces/IBlueprintManager.sol";
// import {IMarketMakerImplementation} from "../interfaces/IMarketMakerImplementation.sol";

contract MMFactory {
	IBlueprintManager immutable public manager;

	constructor(IBlueprintManager _manager) {
		manager = _manager;
	}

	function deployMM(
		address holder,
		address operator,
		uint256 delay,
		address implementation
	) public returns (MM) {
		return new MM(manager, holder, operator, delay, implementation);
	}
}
