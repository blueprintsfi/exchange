// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IMMFactory {
	function ragequitTimestamp(address mm) external view returns (uint256 ts);
	function ragequit(address mm, bool status) external;
	function deployMM(
		address holder,
		address operator,
		uint256 delay,
		address implementation
	) external returns (address);
}