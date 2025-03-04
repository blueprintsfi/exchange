// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {TokenOp} from "../../lib/core/src/interfaces/IBlueprintManager.sol";

function hashTokenOps(TokenOp[] calldata ops) pure returns (bytes32 hash) {
    bytes32 TOKENOP_TYPEHASH = keccak256(
        "TokenOp(uint256 tokenId,uint256 amount)"
    );

    assembly ("memory-safe") {
        // Get free memory pointer
        let ptr := mload(0x40)

        // Calculate total hash length (32 bytes per hash)
        let hashLen := shl(5, ops.length)

        // Calculate pointer to current hash
        let hashptr := add(ptr, hashLen)

        // Store type hash
        mstore(hashptr, TOKENOP_TYPEHASH)

        // Calculate pointer to hash data
        let hashdataptr := add(hashptr, 0x20)

        // Initialize next hash pointer
        let nextHashPtr := ptr

        // Loop through all operations
        for {} lt(nextHashPtr, hashptr) {nextHashPtr := add(nextHashPtr, 0x20)} {
            // Copy operation data from calldata
            calldatacopy(hashdataptr, ops.offset, 0x40)

            // Store hash of current operation
            mstore(nextHashPtr, keccak256(hashptr, 0x60))

            // Move to next operation in calldata
            ops.offset := add(ops.offset, 0x40)
        }

        // Calculate final hash
        hash := keccak256(ptr, hashLen)
    }
}
