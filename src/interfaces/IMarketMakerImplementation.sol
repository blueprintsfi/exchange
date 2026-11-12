// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {TokenOp} from "core/interfaces/IBlueprintManager.sol";

interface IMarketMakerImplementation {
	function executeAction(bytes calldata action) external returns (
		uint256 subaccount,
		TokenOp[] memory give,
		TokenOp[] memory take
	);
}
