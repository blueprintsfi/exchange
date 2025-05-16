// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "forge-std/Test.sol";
import "forge-std/console.sol";

import {zero, oneOpArray} from "../lib/core/src/blueprints/BasicBlueprint.sol";
import {BlueprintManager, BlueprintCall, HashLib, TokenOp} from "../lib/core/src/BlueprintManager.sol";
import {MMProxy, MMFactory} from "../src/mm/MMFactory.sol";

contract StableSwap {
	uint256 immutable token0;
	uint256 immutable token1;
	uint256 immutable fee;

	constructor(uint256 t0, uint256 t1, uint256 f) {
		require(fee <= 1e6);
		token0 = t0;
		token1 = t1;
		fee = f;
	}

	function swap(bool forward, uint256 amountIn) public view returns (uint256, TokenOp[] memory, TokenOp[] memory) {
		uint256 amountOut = amountIn * (1e6 - fee) / 1e6;
		TokenOp[] memory give = oneOpArray(forward ? token1 : token0, amountOut);
		TokenOp[] memory take = oneOpArray(forward ? token0 : token1, amountIn);

		return (0, give, take);
	}
}

contract MMTest is Test {
	uint256 token0 = HashLib.hash(address(this), 0);
	uint256 token1 = HashLib.hash(address(this), 1);

	address holder = address(0xaabb);
	address operator = address(0xbbcc);
	uint256 delay = 1 days;

	BlueprintManager public manager = new BlueprintManager();
	MMFactory public factory = new MMFactory(manager);
	address public zeroFeeSwapImpl = address(new StableSwap(token0, token1, 0));
	// address public fee1pcSwapImpl = address(new StableSwap(token0, token1, 10_000));

	address zeroFeeSwap = factory.deployMM(holder, operator, delay, zeroFeeSwapImpl);
	// address fee1pcSwap = factory.deployMM(holder, operator, delay, fee1pcSwapImpl);

	function setUp() public {
		manager.mint(zeroFeeSwap, 0, type(uint256).max - 1e9 ether);
		manager.mint(zeroFeeSwap, 1, type(uint256).max - 1e9 ether);
		manager.mint(address(this), 0, 1e9 ether);
		manager.mint(address(this), 1, 1e9 ether);
	}

	function run() public {
		test_swap1();
	}

	function test_swap1() public {
		vm.prank(operator);
		MMProxy(zeroFeeSwap).allowActions(true);

		BlueprintCall[] memory calls = new BlueprintCall[](1);
		calls[0] = BlueprintCall(
			address(this),
			0,
			address(zeroFeeSwap),
			abi.encodeCall(
				StableSwap.swap,
				(true, 1000 ether)
			),
			bytes32(0)
		);
		manager.cook(address(0), calls);

		vm.prank(operator);
		MMProxy(zeroFeeSwap).allowActions(false);

		assertEq(manager.balanceOf(address(this), token0), 1e9 ether - 1000 ether);
		assertEq(manager.balanceOf(address(this), token1), 1e9 ether + 1000 ether);
	}
}
