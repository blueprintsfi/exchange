// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";
import {IBlueprintManager} from "core/interfaces/IBlueprintManager.sol";
import {BlueprintManager} from "core/BlueprintManager.sol"; // todo: change to interface and add transfers to the interface
import {BasicBlueprint, TokenOp} from "core/blueprints/BasicBlueprint.sol";
import {gcd} from "core/libraries/Math.sol";
import {IFexEvents} from "./interfaces/IFexEvents.sol";

struct Swap {
	address holder;
	address operator;
	uint256 deadlineAndNonce;
	uint256 delay;
	TokenOp[] inputs; //  [A: 20, B: 35] ;;  gcd = 5  ;;   [4, 7]
	TokenOp[] outputs; // [C: 35, D: 14] ;;  gcd = 7 ;;   [5, 2]   ;;    [20, 3]
}

struct SwapExecution {
	Swap swap;
	uint256 output;
}

function gcd(TokenOp[] calldata ops) pure returns (uint256 res) {
	res = 0;
	for (uint256 i = 0; i < ops.length; i++)
		res = gcd(res, ops[i].amount);
}

contract fExchange is BasicBlueprint, IFexEvents {
	mapping (address holder =>
		mapping (uint256 tokenId =>
			mapping (address operator =>
				mapping (uint256 delay => uint256 balance)))) public balances;
	mapping (address holder =>
		mapping (address operator =>
			mapping (uint256 delay => uint256 withdrawalNonce))) public nonces;
	mapping (address holder =>
		mapping (address operator =>
			mapping (uint256 delay => uint256 timestamp))) public ragequitTime;
	mapping (address holder => mapping (bytes32 orderId => uint256 filled)) public fill;
	mapping (address holder => mapping (bytes32 orderId => uint256 timestamp)) public cancelled;

	constructor(IBlueprintManager _blueprintManager)
		BasicBlueprint(_blueprintManager) {}

	// deposit using cook
	function executeAction(bytes calldata action) external onlyManager returns (
		TokenOp[] memory /*mint*/,
		TokenOp[] memory /*burn*/,
		TokenOp[] memory /*give*/,
		TokenOp[] memory /*take*/
	) {
		(address depositFor, address operator, uint256 delay, TokenOp[] memory deposits) =
			abi.decode(action, (address, address, uint256, TokenOp[]));

		uint256 len = deposits.length;
		for (uint256 i = 0; i < len; i++)
			balances[depositFor][deposits[i].tokenId][operator][delay] += deposits[i].amount;

		emit Deposit(depositFor, operator, delay, deposits);

		return (zero(), zero(), zero(), deposits);
	}

	function ragequit(address operator, uint256 delay) external {
		// todo: custom error
		require(ragequitTime[msg.sender][operator][delay] == 0);
		ragequitTime[msg.sender][operator][delay] = block.timestamp;
		emit RageQuit(msg.sender, operator, delay, block.timestamp);
	}

	function unragequit(address operator, uint256 delay) external {
		require(ragequitTime[msg.sender][operator][delay] != 0);
		ragequitTime[msg.sender][operator][delay] = 0;
		emit UnrageQuit(msg.sender, operator, delay);
	}

	function rageWithdraw(address operator, uint256 delay, TokenOp[] calldata withdrawals) external {
		// todo: custom error
		uint256 ts = ragequitTime[msg.sender][operator][delay];
		require(ts + delay < block.timestamp);
		require(ts != 0);

		uint256 len = withdrawals.length;
		for (uint256 i = 0; i < len; i++) {
			uint256 tokenId = withdrawals[i].tokenId;
			uint256 amount = withdrawals[i].amount;
			balances[msg.sender][tokenId][operator][delay] -= amount;
			// todo: create a batch transfer in Blueprint Manager using a TokenOp array
			BlueprintManager(address(blueprintManager)).transfer(msg.sender, tokenId, amount); // todo: ughh use interface
		}
	}

	function withdraw(
		address holder,
		address to,
		address operator,
		uint256 delay,
		uint256 nonce,
		TokenOp[] calldata withdrawals,
		bytes calldata signature
	) external {
		// todo: custom errors
		require(holder == msg.sender || holder == to);
		require(SignatureCheckerLib.isValidSignatureNowCalldata(
			operator,
			// todo: is there any upside for including the operator in the signed data?
			keccak256(abi.encode(holder, delay, nonce, withdrawals)),
			signature
		));
		require(nonces[holder][operator][delay] < nonce);
		nonces[holder][operator][delay] = nonce;

		uint256 len = withdrawals.length;
		for (uint256 i = 0; i < len; i++) {
			uint256 tokenId = withdrawals[i].tokenId;
			uint256 amount = withdrawals[i].amount;
			balances[msg.sender][tokenId][operator][delay] -= amount;
			// todo: create a batch transfer in Blueprint Manager using a TokenOp array
			BlueprintManager(address(blueprintManager)).transfer(msg.sender, tokenId, amount); // todo: ughh use interface
		}
	}

	function signOrder(bytes32 orderId) external {
		require(fill[msg.sender][orderId] == 0);
		fill[msg.sender][orderId] = 1;

		emit OrderSigned(msg.sender, orderId);
		// todo: how will we know the details? emitted by a contract or here, with the whole order as the argument?
	}

	function initCancel(bytes32[] calldata orderIds) external {
		for (uint256 i = 0; i < orderIds.length; i++) {
			require(cancelled[msg.sender][orderIds[i]] == 0);
			cancelled[msg.sender][orderIds[i]] = block.timestamp;
		}
	}

	function cancel(Swap[] calldata swaps) external {
		for (uint256 i = 0; i < swaps.length; i++) {
			Swap calldata swap = swaps[i];
			require(swap.holder == msg.sender);
			bytes32 orderId = keccak256(abi.encode(swap));
			uint256 ts = cancelled[msg.sender][orderId];
			require(ts != 0 && ts + swap.delay < block.timestamp);
			fill[msg.sender][orderId] = type(uint256).max;
		}
	}

	function operatorCancel(Swap[] calldata swaps) external {
		for (uint256 i = 0; i < swaps.length; i++) {
			Swap calldata swap = swaps[i];
			require(swap.operator == msg.sender);
			bytes32 orderId = keccak256(abi.encode(swap));
			fill[swap.holder][orderId] = type(uint256).max;
		}
	}

	function getSwapData(Swap calldata swap, uint256 previousFill, uint256 newFill) internal pure returns (
		uint256 amountInGcd,
		uint256 amountOutGcd,
		uint256 amountIn
	) {
		amountInGcd = gcd(swap.inputs);
		amountOutGcd = gcd(swap.outputs);

		require(newFill < amountOutGcd); // todo: custom error

		uint256 previousInput = amountInGcd * previousFill / amountOutGcd;
		uint256 newInput = amountInGcd * newFill / amountOutGcd;

		amountIn = newInput - previousInput;
	}

	function executeSwaps(SwapExecution[] calldata swaps, bytes[] calldata signatures) external {
		for (uint256 i = 0; i < swaps.length; i++) {
			SwapExecution calldata swapEx = swaps[i];
			Swap calldata swap = swapEx.swap;
			bytes32 orderId = keccak256(abi.encode(swap));

			require(block.timestamp <= (swap.deadlineAndNonce >> 128));
			require(swap.operator == msg.sender); // todo: operator shouldn't be in calldata then

			uint256 previousFill = fill[swap.holder][orderId];

			if (previousFill == 0) {
				require(SignatureCheckerLib.isValidSignatureNowCalldata(
					swap.holder,
					orderId,
					signatures[i]
				));
			} else {
				previousFill--;
			}
			uint256 newFill = previousFill + swapEx.output; // todo revert overflow no message
			fill[swap.holder][orderId] = newFill + 1;
			(
				uint256 amountInGcd,
				uint256 amountOutGcd,
				uint256 amountIn
			) = getSwapData(swap, previousFill, newFill);

			TokenOp[] calldata inputs = swap.inputs;
			for (uint256 j = 0; j < inputs.length; j++) { // todo: use flash accounting
				(uint256 tokenId, uint256 amount) = (inputs[j].tokenId, inputs[j].amount);
				amount = amount / amountInGcd * amountIn;
				balances[swap.holder][tokenId][msg.sender][swap.delay] -= amount;
				balances[msg.sender][tokenId][msg.sender][0] += amount;
			}

			TokenOp[] calldata outputs = swap.outputs;
			for (uint256 j = 0; j < outputs.length; j++) { // todo: use flash accounting
				(uint256 tokenId, uint256 amount) = (outputs[j].tokenId, outputs[j].amount);
				amount = amount / amountOutGcd * swapEx.output;
				balances[swap.holder][tokenId][msg.sender][swap.delay] += amount;
				balances[msg.sender][tokenId][msg.sender][0] -= amount; // todo: extremely important to use flash accounting here
			}
		}
	}
}



// deposits:
// 	- (done) through cook
// 	- (should we?) through approvals/operators
// - withdrawals:
// 	- (done) force withdrawal process // withdraw
// 	- (done) with operator's signature
// - swaps:
// 	- (done) many to many like a basket
// - cancellations:
// 	- (done) by operator
// 	- (done) by user, with delay








// history
// - swaps:
// 	- one to one, many to one, one to many, maybe many to many?




