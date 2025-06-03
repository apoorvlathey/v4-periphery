// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ParseBytes} from "@uniswap/v4-core/src/libraries/ParseBytes.sol";

library QuoterV2Revert {
    using QuoterV2Revert for bytes;
    using ParseBytes for bytes;

    /// @notice error thrown when invalid revert bytes are thrown by the quote
    error UnexpectedRevertBytes(bytes revertData);

    /// @notice error thrown containing the quote as the data, to be caught and parsed later
    error QuoteSwap(uint256 amount, uint160 sqrtPriceX96After, int24 tickAfter);
    error QuoteSwapList(uint256 amount, uint160[] sqrtPriceX96AfterList, int24[] tickAfterList);

    /// @notice reverts, where the revert data is the provided bytes
    /// @dev called when quoting, to record the quote amount in an error
    /// @dev QuoteSwap is used to differentiate this error from other errors thrown when simulating the swap
    function revertQuote(uint256 quoteAmount, uint160 sqrtPriceX96After, int24 tickAfter) internal pure {
        revert QuoteSwap(quoteAmount, sqrtPriceX96After, tickAfter);
    }

    function revertQuoteList(uint256 quoteAmount, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList) internal pure {
        revert QuoteSwapList(quoteAmount, sqrtPriceX96AfterList, tickAfterList);
    }

    /// @notice reverts using the revertData as the reason
    /// @dev to bubble up both the valid QuoteSwap(amount) error, or an alternative error thrown during simulation
    function bubbleReason(bytes memory revertData) internal pure {
        // mload(revertData): the length of the revert data
        // add(revertData, 0x20): a pointer to the start of the revert data
        assembly ("memory-safe") {
            revert(add(revertData, 0x20), mload(revertData))
        }
    }

    /// @notice validates whether a revert reason is a valid swap quote or not
    /// if valid, it decodes the quote to return. Otherwise it reverts.
    function parseQuoteSwap(bytes memory reason) internal pure returns (uint256 quoteAmount, uint160 sqrtPriceX96After, int24 tickAfter) {
        // If the error doesnt start with QuoteSwap, we know this isnt a valid quote to parse
        // Instead it is another revert that was triggered somewhere in the simulation
        if (reason.parseSelector() != QuoteSwap.selector) {
            revert UnexpectedRevertBytes(reason);
        }

        // Create a new bytes array without the selector for abi.decode
        bytes memory dataWithoutSelector;
        assembly ("memory-safe") {
            // Length of new bytes (without 4-byte selector)
            let len := sub(mload(reason), 4)

            // Allocate memory for the new bytes
            dataWithoutSelector := mload(0x40)
            mstore(dataWithoutSelector, len) // store length

            // Source pointer: reason data + 32-byte length field + 4-byte selector
            let src := add(reason, 36)
            // Destination pointer: start of dataWithoutSelector content
            let dest := add(dataWithoutSelector, 32)

            // Copy in 32-byte chunks
            for { let i := 0 } lt(i, len) { i := add(i, 32) } {
                mstore(add(dest, i), mload(add(src, i)))
            }

            // Update free memory pointer
            mstore(0x40, add(dest, and(add(len, 31), not(31))))
        }
        
        (quoteAmount, sqrtPriceX96After, tickAfter) = abi.decode(dataWithoutSelector, (uint256, uint160, int24));
    }

    function parseQuoteSwapList(bytes memory reason) internal pure returns (uint256 quoteAmount, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList) {
        // If the error doesnt start with QuoteSwapList, we know this isnt a valid quote to parse
        // Instead it is another revert that was triggered somewhere in the simulation
        if (reason.parseSelector() != QuoteSwapList.selector) {
            revert UnexpectedRevertBytes(reason);
        }

        // Create a new bytes array without the selector for abi.decode
        bytes memory dataWithoutSelector;
        assembly ("memory-safe") {
            // Length of new bytes (without 4-byte selector)
            let len := sub(mload(reason), 4)

            // Allocate memory for the new bytes
            dataWithoutSelector := mload(0x40)
            mstore(dataWithoutSelector, len) // store length

            // Source pointer: reason data + 32-byte length field + 4-byte selector
            let src := add(reason, 36)
            // Destination pointer: start of dataWithoutSelector content
            let dest := add(dataWithoutSelector, 32)

            // Copy in 32-byte chunks
            for { let i := 0 } lt(i, len) { i := add(i, 32) } {
                mstore(add(dest, i), mload(add(src, i)))
            }

            // Update free memory pointer
            mstore(0x40, add(dest, and(add(len, 31), not(31))))
        }
        
        (quoteAmount, sqrtPriceX96AfterList, tickAfterList) = abi.decode(dataWithoutSelector, (uint256, uint160[], int24[]));
    }
}
