// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IV4QuoterV2} from "../interfaces/IV4QuoterV2.sol";
import {PathKey} from "../libraries/PathKey.sol";
import {QuoterV2Revert} from "../libraries/QuoterV2Revert.sol";
import {BaseV4QuoterV2} from "../base/BaseV4QuoterV2.sol";
import {Locker} from "../libraries/Locker.sol";
import {IMsgSender} from "../interfaces/IMsgSender.sol";

/// @title V4Quoter
/// @notice Supports quoting the delta amounts for exact input or exact output swaps.
/// @dev These functions are not marked view because they rely on calling non-view functions and reverting
/// to compute the result. They are also not gas efficient and should not be called on-chain.
contract V4QuoterV2 is IV4QuoterV2, BaseV4QuoterV2 {
    struct QuoteCache {
        int128 deltaIn;
        int128 deltaOut;
        uint160 sqrtPriceX96After;
        int24 tickAfter;
    }

    struct QuoteResult {
        int128[] deltaAmounts;
        uint160[] sqrtPriceX96AfterList;
        int24[] tickAfterList;
    }

    constructor(IPoolManager _poolManager) BaseV4QuoterV2(_poolManager) {}

    modifier setMsgSender() {
        Locker.set(msg.sender);
        _; // execute the function
        Locker.set(address(0)); // reset the locker
    }

    /// @inheritdoc IV4QuoterV2
    function quoteExactInputSingle(QuoteExactSingleParams memory params)
        external
        setMsgSender
        returns (uint256 amountOut, uint160 sqrtPriceX96After, int24 tickAfter, uint256 gasEstimate)
    {
        uint256 gasBefore = gasleft();
        try poolManager.unlock(abi.encodeCall(this._quoteExactInputSingle, (params))) {}
        catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            // Extract the quote from QuoteSwap error, or throw if the quote failed
            (amountOut, sqrtPriceX96After, tickAfter) = QuoterV2Revert.parseQuoteSwap(reason);
        }
    }

    /// @inheritdoc IV4QuoterV2
    function quoteExactInput(QuoteExactParams memory params)
        external
        setMsgSender
        returns (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList, uint256 gasEstimate)
    {
        uint256 gasBefore = gasleft();
        try poolManager.unlock(abi.encodeCall(this._quoteExactInput, (params))) {}
        catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            // Extract the quote from QuoteSwap error, or throw if the quote failed
            (amountOut, sqrtPriceX96AfterList, tickAfterList) = QuoterV2Revert.parseQuoteSwapList(reason);
        }
    }

    /// @inheritdoc IV4QuoterV2
    function quoteExactOutputSingle(QuoteExactSingleParams memory params)
        external
        setMsgSender
        returns (uint256 amountIn, uint160 sqrtPriceX96After, int24 tickAfter, uint256 gasEstimate)
    {
        uint256 gasBefore = gasleft();
        try poolManager.unlock(abi.encodeCall(this._quoteExactOutputSingle, (params))) {}
        catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            // Extract the quote from QuoteSwap error, or throw if the quote failed
            (amountIn, sqrtPriceX96After, tickAfter) = QuoterV2Revert.parseQuoteSwap(reason);
        }
    }

    /// @inheritdoc IV4QuoterV2
    function quoteExactOutput(QuoteExactParams memory params)
        external
        setMsgSender
        returns (uint256 amountIn, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList, uint256 gasEstimate)
    {
        uint256 gasBefore = gasleft();
        try poolManager.unlock(abi.encodeCall(this._quoteExactOutput, (params))) {}
        catch (bytes memory reason) {
            gasEstimate = gasBefore - gasleft();
            // Extract the quote from QuoteSwap error, or throw if the quote failed
            (amountIn, sqrtPriceX96AfterList, tickAfterList) = QuoterV2Revert.parseQuoteSwapList(reason);
        }
    }

    /// @dev external function called within the _unlockCallback, to simulate an exact input swap, then revert with the result
    function _quoteExactInput(QuoteExactParams calldata params) external selfOnly returns (bytes memory) {
        uint256 pathLength = params.path.length;
        BalanceDelta swapDelta;
        uint128 amountIn = params.exactAmount;
        Currency inputCurrency = params.exactCurrency;
        PathKey calldata pathKey;

        QuoteResult memory result = QuoteResult({
            deltaAmounts: new int128[](pathLength + 1),
            sqrtPriceX96AfterList: new uint160[](pathLength),
            tickAfterList: new int24[](pathLength)
        });
        QuoteCache memory cache;

        for (uint256 i = 0; i < pathLength; i++) {
            pathKey = params.path[i];
            (PoolKey memory poolKey, bool zeroForOne) = pathKey.getPoolAndSwapDirection(inputCurrency);

            (swapDelta, cache.sqrtPriceX96After, cache.tickAfter) = _swap(poolKey, zeroForOne, -int256(int128(amountIn)), pathKey.hookData);

            amountIn = zeroForOne ? uint128(swapDelta.amount1()) : uint128(swapDelta.amount0());
            inputCurrency = pathKey.intermediateCurrency;

            (cache.deltaIn, cache.deltaOut) = zeroForOne
                ? (-swapDelta.amount0(), -swapDelta.amount1())
                : (-swapDelta.amount1(), -swapDelta.amount0());
            result.deltaAmounts[i] += cache.deltaIn;
            result.deltaAmounts[i + 1] += cache.deltaOut;

            result.sqrtPriceX96AfterList[i] = cache.sqrtPriceX96After;
            result.tickAfterList[i] = cache.tickAfter;
        }
        // amountIn after the loop actually holds the amountOut of the trade
        QuoterV2Revert.revertQuoteList(amountIn, result.sqrtPriceX96AfterList, result.tickAfterList);
    }

    /// @dev external function called within the _unlockCallback, to simulate a single-hop exact input swap, then revert with the result
    function _quoteExactInputSingle(QuoteExactSingleParams calldata params) external selfOnly returns (bytes memory) {
        (BalanceDelta swapDelta, uint160 sqrtPriceX96After, int24 tickAfter) =
            _swap(params.poolKey, params.zeroForOne, -int256(int128(params.exactAmount)), params.hookData);

        // the output delta of a swap is positive
        uint256 amountOut = params.zeroForOne ? uint128(swapDelta.amount1()) : uint128(swapDelta.amount0());
        QuoterV2Revert.revertQuote(amountOut, sqrtPriceX96After, tickAfter);
    }

    /// @dev external function called within the _unlockCallback, to simulate an exact output swap, then revert with the result
    function _quoteExactOutput(QuoteExactParams calldata params) external selfOnly returns (bytes memory) {
        uint256 pathLength = params.path.length;
        BalanceDelta swapDelta;
        uint128 amountOut = params.exactAmount;
        Currency outputCurrency = params.exactCurrency;
        PathKey calldata pathKey;

        QuoteResult memory result = QuoteResult({
            deltaAmounts: new int128[](pathLength + 1),
            sqrtPriceX96AfterList: new uint160[](pathLength),
            tickAfterList: new int24[](pathLength)
        });
        QuoteCache memory cache;

        for (uint256 i = pathLength; i > 0; i--) {
            pathKey = params.path[i - 1];
            (PoolKey memory poolKey, bool oneForZero) = pathKey.getPoolAndSwapDirection(outputCurrency);

            (swapDelta, cache.sqrtPriceX96After, cache.tickAfter) = _swap(poolKey, !oneForZero, int256(uint256(amountOut)), pathKey.hookData);

            amountOut = oneForZero ? uint128(-swapDelta.amount1()) : uint128(-swapDelta.amount0());

            outputCurrency = pathKey.intermediateCurrency;

            (cache.deltaIn, cache.deltaOut) = !oneForZero
                ? (-swapDelta.amount0(), -swapDelta.amount1())
                : (-swapDelta.amount1(), -swapDelta.amount0());
            result.deltaAmounts[i - 1] += cache.deltaIn;
            result.deltaAmounts[i] += cache.deltaOut;

            result.sqrtPriceX96AfterList[i - 1] = cache.sqrtPriceX96After;
            result.tickAfterList[i - 1] = cache.tickAfter;
        }
        // amountOut after the loop exits actually holds the amountIn of the trade
        QuoterV2Revert.revertQuoteList(amountOut, result.sqrtPriceX96AfterList, result.tickAfterList);
    }

    /// @dev external function called within the _unlockCallback, to simulate a single-hop exact output swap, then revert with the result
    function _quoteExactOutputSingle(QuoteExactSingleParams calldata params) external selfOnly returns (bytes memory) {
        (BalanceDelta swapDelta, uint160 sqrtPriceX96After, int24 tickAfter) =
            _swap(params.poolKey, params.zeroForOne, int256(uint256(params.exactAmount)), params.hookData);

        // the input delta of a swap is negative so we must flip it
        uint256 amountIn = params.zeroForOne ? uint128(-swapDelta.amount0()) : uint128(-swapDelta.amount1());
        QuoterV2Revert.revertQuote(amountIn, sqrtPriceX96After, tickAfter);
    }

    /// @inheritdoc IMsgSender
    function msgSender() external view returns (address) {
        // despite using the Locker library, V4Quoter does not have a reentrancy lock
        return Locker.get();
    }
}
