// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PathKey} from "../libraries/PathKey.sol";
import {IImmutableState} from "./IImmutableState.sol";
import {IMsgSender} from "./IMsgSender.sol";

/// @title IV4QuoterV2
/// @notice Interface for the V4QuoterV2 contract
interface IV4QuoterV2 is IImmutableState, IMsgSender {
    struct QuoteExactSingleParams {
        PoolKey poolKey;
        bool zeroForOne;
        uint128 exactAmount;
        bytes hookData;
    }

    struct QuoteExactParams {
        Currency exactCurrency;
        PathKey[] path;
        uint128 exactAmount;
    }

    /// @notice Returns the delta amounts for a given exact input swap of a single pool
    /// @param params The params for the quote, encoded as `QuoteExactSingleParams`
    /// poolKey The key for identifying a V4 pool
    /// zeroForOne If the swap is from currency0 to currency1
    /// exactAmount The desired input amount
    /// hookData arbitrary hookData to pass into the associated hooks
    /// @return amountOut The output quote for the exactIn swap
    /// @return sqrtPriceX96After The sqrtPriceX96 after the swap
    /// @return tickAfter The tick after the swap
    /// @return gasEstimate Estimated gas units used for the swap
    function quoteExactInputSingle(QuoteExactSingleParams memory params)
        external
        returns (uint256 amountOut, uint160 sqrtPriceX96After, int24 tickAfter, uint256 gasEstimate);

    /// @notice Returns the delta amounts along the swap path for a given exact input swap
    /// @param params the params for the quote, encoded as 'QuoteExactParams'
    /// currencyIn The input currency of the swap
    /// path The path of the swap encoded as PathKeys that contains currency, fee, tickSpacing, and hook info
    /// exactAmount The desired input amount
    /// @return amountOut The output quote for the exactIn swap
    /// @return sqrtPriceX96AfterList The sqrtPriceX96 after the swap for each pool in the path
    /// @return tickAfterList The tick after the swap for each pool in the path
    /// @return gasEstimate Estimated gas units used for the swap
    function quoteExactInput(QuoteExactParams memory params)
        external
        returns (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList, uint256 gasEstimate);

    /// @notice Returns the delta amounts for a given exact output swap of a single pool
    /// @param params The params for the quote, encoded as `QuoteExactSingleParams`
    /// poolKey The key for identifying a V4 pool
    /// zeroForOne If the swap is from currency0 to currency1
    /// exactAmount The desired output amount
    /// hookData arbitrary hookData to pass into the associated hooks
    /// @return amountIn The input quote for the exactOut swap
    /// @return sqrtPriceX96After The sqrtPriceX96 after the swap
    /// @return tickAfter The tick after the swap
    /// @return gasEstimate Estimated gas units used for the swap
    function quoteExactOutputSingle(QuoteExactSingleParams memory params)
        external
        returns (uint256 amountIn, uint160 sqrtPriceX96After, int24 tickAfter, uint256 gasEstimate);

    /// @notice Returns the delta amounts along the swap path for a given exact output swap
    /// @param params the params for the quote, encoded as 'QuoteExactParams'
    /// currencyOut The output currency of the swap
    /// path The path of the swap encoded as PathKeys that contains currency, fee, tickSpacing, and hook info
    /// exactAmount The desired output amount
    /// @return amountIn The input quote for the exactOut swap
    /// @return sqrtPriceX96AfterList The sqrtPriceX96 after the swap for each pool in the path
    /// @return tickAfterList The tick after the swap for each pool in the path
    /// @return gasEstimate Estimated gas units used for the swap
    function quoteExactOutput(QuoteExactParams memory params)
        external
        returns (uint256 amountIn, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList, uint256 gasEstimate);
}
