// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";
import {IBlueprintManager} from "core/interfaces/IBlueprintManager.sol";
import {BlueprintManager} from "core/BlueprintManager.sol"; // todo: change to interface and add transfers to the interface
import {BasicBlueprint, TokenOp} from "core/blueprints/BasicBlueprint.sol";
import {gcd} from "core/libraries/Math.sol";

struct Swap {
	address holder;
	address operator;
	uint256 delay;
	address subaccount;
	uint256 deadlineAndNonce;
	TokenOp[] inputs;
	TokenOp[] outputs;
}

struct Permit {
	address holder;
	address operator;
	uint256 delay;
	address subaccount;
	uint256 deadlineAndNonce;
	TokenOp[] tokens;
}

struct SwapExecution {
	Swap swap;
	uint256 output;
}

struct UserData {
	mapping (uint256 tokenId => uint256 balance) balances;
	mapping (address subaccount => mapping (uint256 tokenId => uint256 allowance)) allowed;
	mapping (address subaccount => bool deactivated) deactivated;
	uint256 nonce;
	uint256 ragequitTime;
}

function gcd(TokenOp[] calldata ops) pure returns (uint256 res) {
	res = 0;
	for (uint256 i = 0; i < ops.length; i++)
		res = gcd(res, ops[i].amount);
}

contract fExchange is BasicBlueprint {
	/// @notice Emitted when tokens are deposited into the exchange
	/// @param depositFor The address receiving the deposit
	/// @param operator The operator address
	/// @param delay The delay period for the deposit
	/// @param deposits Array of token operations containing deposit details
	event Deposit(address indexed depositFor, address indexed operator, uint256 indexed delay, TokenOp[] deposits);

	/// @notice Emitted when a user initiates ragequit
	/// @param holder The address initiating ragequit
	/// @param operator The operator address
	/// @param delay The delay period
	/// @param timestamp When the ragequit was initiated
	event Ragequit(address indexed holder, address indexed operator, uint256 indexed delay, uint256 timestamp);

	/// @notice Emitted when a user cancels their ragequit
	/// @param holder The address canceling ragequit
	/// @param operator The operator address
	/// @param delay The delay period
	event Unragequit(address indexed holder, address indexed operator, uint256 indexed delay);

	/// @notice Emitted when an order is signed
	/// @param holder The address signing the order
	/// @param orderId The unique identifier of the order
	event OrderSigned(address indexed holder, bytes32 indexed orderId);

	mapping (address holder =>
		mapping (address operator =>
			mapping (uint256 delay => UserData data))) public userData;
	mapping (address signer => mapping (bytes32 hash => uint256 filled)) public fill;
	mapping (address signer => mapping (bytes32 hash => uint256 timestamp)) public cancelled;

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
			userData[depositFor][operator][delay].balances[deposits[i].tokenId] += deposits[i].amount;

		emit Deposit(depositFor, operator, delay, deposits);

		return (zero(), zero(), zero(), deposits);
	}

	function getBalance(
		address holder,
		address operator,
		uint256 delay,
		uint256 tokenId
	) external view returns (uint256 balance) {
		balance = userData[holder][operator][delay].balances[tokenId];
	}

	function getAllowed(
		address holder,
		address operator,
		uint256 delay,
		address subaccount,
		uint256 tokenId
	) external view returns (uint256 allowance) {
		allowance = userData[holder][operator][delay].allowed[subaccount][tokenId];
	}

	function getDeactivationStatus(
		address holder,
		address operator,
		uint256 delay,
		address subaccount
	) external view returns (bool deactivated) {
		deactivated = userData[holder][operator][delay].deactivated[subaccount];
	}

	function ragequit(address operator, uint256 delay) external {
		// todo: custom error
		require(userData[msg.sender][operator][delay].ragequitTime == 0);
		userData[msg.sender][operator][delay].ragequitTime = block.timestamp;
		emit Ragequit(msg.sender, operator, delay, block.timestamp);
	}

	function unragequit(address operator, uint256 delay) external {
		require(userData[msg.sender][operator][delay].ragequitTime != 0);
		userData[msg.sender][operator][delay].ragequitTime = 0;
		emit Unragequit(msg.sender, operator, delay);
	}

	function rageWithdraw(address operator, uint256 delay, TokenOp[] calldata withdrawals) external {
		// todo: custom error
		uint256 ts = userData[msg.sender][operator][delay].ragequitTime;
		require(ts + delay < block.timestamp);
		require(ts != 0);

		uint256 len = withdrawals.length;
		for (uint256 i = 0; i < len; i++) {
			uint256 tokenId = withdrawals[i].tokenId;
			uint256 amount = withdrawals[i].amount;
			userData[msg.sender][operator][delay].balances[tokenId] -= amount;
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
		require(userData[holder][operator][delay].nonce < nonce);
		userData[holder][operator][delay].nonce = nonce;

		uint256 len = withdrawals.length;
		for (uint256 i = 0; i < len; i++) {
			uint256 tokenId = withdrawals[i].tokenId;
			uint256 amount = withdrawals[i].amount;
			userData[msg.sender][operator][delay].balances[tokenId] -= amount;
			// todo: create a batch transfer in Blueprint Manager using a TokenOp array
			BlueprintManager(address(blueprintManager)).transfer(msg.sender, tokenId, amount); // todo: ughh use interface
		}
	}

	function signOrder(bytes32 orderId) external {
		require(fill[msg.sender][orderId] == 0);
		fill[msg.sender][orderId] = 1;

		emit OrderSigned(msg.sender, orderId);
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

	function setDeactivationStatus(
		address operator,
		uint256 delay,
		address[] calldata subaccounts,
		bool[] calldata status
	) external {
		require(subaccounts.length == status.length);

		for (uint256 i = 0; i < subaccounts.length; i++)
			userData[msg.sender][operator][delay].deactivated[subaccounts[i]] = status[i];

		// todo: add event
	}

	function operatorDeactivate( // todo: batch with other actions?
		address holder,
		uint256 delay,
		address[] calldata subaccounts
	) external {
		for (uint256 i = 0; i < subaccounts.length; i++)
			userData[holder][msg.sender][delay].deactivated[subaccounts[i]] = true;

		// todo: add event
	}

	function operatorCancel(Swap[] calldata swaps) external {
		for (uint256 i = 0; i < swaps.length; i++) {
			Swap calldata swap = swaps[i];
			require(swap.operator == msg.sender);
			bytes32 orderId = keccak256(abi.encode(swap));
			fill[swap.holder][orderId] = type(uint256).max;
		}
	}

	function approveSubaccount(Permit calldata permit, bytes calldata signature) external { // todo: in a batch? only operator?
		bytes32 permitId = keccak256(abi.encode(permit));
		require(fill[permit.holder][permitId] == 0);
		fill[permit.holder][permitId] = 1;
		if (msg.sender != permit.holder) {
			require(msg.sender == permit.operator);
			require(SignatureCheckerLib.isValidSignatureNowCalldata(
				permit.holder,
				permitId,
				signature
			));
		}
		require(block.timestamp <= (permit.deadlineAndNonce >> 128));
		UserData storage userState = userData[permit.holder][permit.operator][permit.delay];

		TokenOp[] calldata tokens = permit.tokens;
		for (uint256 i = 0; i < tokens.length; i++)
			userState.allowed[permit.subaccount][tokens[i].tokenId] += tokens[i].amount;
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
		UserData storage operatorState = userData[msg.sender][msg.sender][0];
		for (uint256 i = 0; i < swaps.length; i++) {
			SwapExecution calldata swapEx = swaps[i];
			Swap calldata swap = swapEx.swap;
			address account = swap.subaccount;
			address holder = swap.holder;
			address signer = account == address(0) ? holder : account;
			UserData storage userState = userData[swap.holder][msg.sender][swap.delay];
			bytes32 orderId = keccak256(abi.encode(swap));

			require(block.timestamp <= (swap.deadlineAndNonce >> 128));
			require(swap.operator == msg.sender); // todo: operator shouldn't be in calldata then

			uint256 previousFill = fill[signer][orderId];

			if (previousFill == 0) {
				require(SignatureCheckerLib.isValidSignatureNowCalldata(
					signer,
					orderId,
					signatures[i]
				));
			} else {
				previousFill--;
			}
			uint256 newFill = previousFill + swapEx.output; // todo revert overflow no message
			fill[signer][orderId] = newFill + 1;
			(
				uint256 amountInGcd,
				uint256 amountOutGcd,
				uint256 amountIn
			) = getSwapData(swap, previousFill, newFill);

			// todo: remove the need for this state access or optimize it
			require(!userState.deactivated[account]);

			TokenOp[] calldata inputs = swap.inputs;
			for (uint256 j = 0; j < inputs.length; j++) { // todo: use flash accounting
				(uint256 tokenId, uint256 amount) = (inputs[j].tokenId, inputs[j].amount);
				amount = amount / amountInGcd * amountIn;

				userState.balances[tokenId] -= amount;
				operatorState.balances[tokenId] += amount;
				if (account != address(0))
					userState.allowed[account][tokenId] -= amount;
			}

			TokenOp[] calldata outputs = swap.outputs;
			for (uint256 j = 0; j < outputs.length; j++) { // todo: use flash accounting
				(uint256 tokenId, uint256 amount) = (outputs[j].tokenId, outputs[j].amount);
				amount = amount / amountOutGcd * swapEx.output;

				userState.balances[tokenId] += amount;
				operatorState.balances[tokenId] -= amount; // todo: extremely important to use flash accounting here
				if (account != address(0))
					userState.allowed[account][tokenId] += amount;
			}
		}
	}
}
