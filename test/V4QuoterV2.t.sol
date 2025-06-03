//SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PathKey} from "../src/libraries/PathKey.sol";
import {Deploy, IV4QuoterV2} from "../test/shared/Deploy.sol";
import {MockMsgSenderHook} from "./mocks/MockMsgSenderHook.sol";
import {console} from "forge-std/console.sol";

// v4-core
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {SafeCast} from "@uniswap/v4-core/src/libraries/SafeCast.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolModifyLiquidityTest} from "@uniswap/v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolId} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {ModifyLiquidityParams} from "@uniswap/v4-core/src/types/PoolOperation.sol";

// solmate
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract QuoterV2Test is Test, Deployers {
    using SafeCast for *;
    using StateLibrary for IPoolManager;

    // Min tick for full range with tick spacing of 60
    int24 internal constant MIN_TICK = -887220;
    // Max tick for full range with tick spacing of 60
    int24 internal constant MAX_TICK = -MIN_TICK;

    uint160 internal constant SQRT_PRICE_100_102 = 78447570448055484695608110440;
    uint160 internal constant SQRT_PRICE_102_100 = 80016521857016594389520272648;

    uint256 internal constant CONTROLLER_GAS_LIMIT = 500000;

    IV4QuoterV2 quoter;

    PoolModifyLiquidityTest positionManager;

    MockERC20 token0;
    MockERC20 token1;
    MockERC20 token2;

    PoolKey key01;
    PoolKey key02;
    PoolKey key12;
    PoolKey key01Hook;

    MockERC20[] tokenPath;

    function setUp() public {
        deployFreshManagerAndRouters();
        quoter = Deploy.v4QuoterV2(address(manager), hex"00");
        positionManager = new PoolModifyLiquidityTest(manager);

        // salts are chosen so that address(token0) < address(token1) && address(token1) < address(token2)
        token0 = new MockERC20("Test0", "0", 18);
        vm.etch(address(0x1111), address(token0).code);
        token0 = MockERC20(address(0x1111));
        token0.mint(address(this), 2 ** 128);

        vm.etch(address(0x2222), address(token0).code);
        token1 = MockERC20(address(0x2222));
        token1.mint(address(this), 2 ** 128);

        vm.etch(address(0x3333), address(token0).code);
        token2 = MockERC20(address(0x3333));
        token2.mint(address(this), 2 ** 128);

        // deploy a hook that reads msgSender
        MockMsgSenderHook msgSenderHook = new MockMsgSenderHook();
        address mockMsgSenderHookAddr = address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG));
        vm.etch(mockMsgSenderHookAddr, address(msgSenderHook).code);

        key01 = createPoolKey(token0, token1, address(0));
        key02 = createPoolKey(token0, token2, address(0));
        key12 = createPoolKey(token1, token2, address(0));
        key01Hook = createPoolKey(token0, token1, mockMsgSenderHookAddr);
        setupPool(key01);
        setupPool(key12);
        setupPool(key01Hook);
        setupPoolMultiplePositions(key02);
    }

    function testQuoterV2_quoteExactInputSingle_ZeroForOne_MultiplePositions() public {
        uint256 amountIn = 10000;
        uint256 expectedAmountOut = 9871;

        (uint256 amountOut, uint160 sqrtPriceX96After, int24 tickAfter,) = quoter.quoteExactInputSingle(
            IV4QuoterV2.QuoteExactSingleParams({
                poolKey: key02,
                zeroForOne: true,
                exactAmount: uint128(amountIn),
                hookData: ZERO_BYTES
            })
        );
        vm.snapshotGasLastCall("QuoterV2_exactInputSingle_zeroForOne_multiplePositions");

        console.log("sqrtPriceX96After:", sqrtPriceX96After);
        console.log("tickAfter:", tickAfter);
        assertEq(amountOut, expectedAmountOut);
    }

    function testQuoterV2_quoteExactInputSingle_OneForZero_MultiplePositions() public {
        uint256 amountIn = 10000;
        uint256 expectedAmountOut = 9871;

        (uint256 amountOut, uint160 sqrtPriceX96After, int24 tickAfter,) = quoter.quoteExactInputSingle(
            IV4QuoterV2.QuoteExactSingleParams({
                poolKey: key02,
                zeroForOne: false,
                exactAmount: uint128(amountIn),
                hookData: ZERO_BYTES
            })
        );
        vm.snapshotGasLastCall("QuoterV2_exactInputSingle_oneForZero_multiplePositions");

        console.log("sqrtPriceX96After:", sqrtPriceX96After);
        console.log("tickAfter:", tickAfter);
        assertEq(amountOut, expectedAmountOut);
    }

    function testQuoterV2_quoteExactInput_0to2_2TicksLoaded() public {
        tokenPath.push(token0);
        tokenPath.push(token2);
        IV4QuoterV2.QuoteExactParams memory params = getExactInputParams(tokenPath, 10000);

        (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactInput(params);

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountOut, 9871);
    }

    function testQuoterV2_quoteExactInput_0to2_2TicksLoaded_initializedAfter() public {
        tokenPath.push(token0);
        tokenPath.push(token2);

        // The swap amount is set such that the active tick after the swap is -120.
        // -120 is an initialized tick for this pool. We check that we don't count it.
        IV4QuoterV2.QuoteExactParams memory params = getExactInputParams(tokenPath, 6200);

        (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactInput(params);

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountOut, 6143);
    }

    function testQuoterV2_quoteExactInput_0to2_1TickLoaded() public {
        tokenPath.push(token0);
        tokenPath.push(token2);

        // The swap amount is set such that the active tick after the swap is -60.
        // -60 is an initialized tick for this pool. We check that we don't count it.
        IV4QuoterV2.QuoteExactParams memory params = getExactInputParams(tokenPath, 4000);

        (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactInput(params);

        vm.snapshotGasLastCall("QuoterV2_quoteExactInput_oneHop_1TickLoaded");

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountOut, 3971);
    }

    function testQuoterV2_quoteExactInput_0to2_0TickLoaded_startingNotInitialized() public {
        tokenPath.push(token0);
        tokenPath.push(token2);
        IV4QuoterV2.QuoteExactParams memory params = getExactInputParams(tokenPath, 10);

        (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactInput(params);

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountOut, 8);
    }

    function testQuoterV2_quoteExactInput_0to2_0TickLoaded_startingInitialized() public {
        setupPoolWithZeroTickInitialized(key02);
        tokenPath.push(token0);
        tokenPath.push(token2);
        IV4QuoterV2.QuoteExactParams memory params = getExactInputParams(tokenPath, 10);

        (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactInput(params);

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountOut, 8);
    }

    function testQuoterV2_quoteExactInput_2to0_2TicksLoaded() public {
        tokenPath.push(token2);
        tokenPath.push(token0);
        IV4QuoterV2.QuoteExactParams memory params = getExactInputParams(tokenPath, 10000);

        (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactInput(params);

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountOut, 9871);
    }

    function testQuoterV2_quoteExactInput_2to0_2TicksLoaded_initializedAfter() public {
        tokenPath.push(token2);
        tokenPath.push(token0);

        // The swap amount is set such that the active tick after the swap is 120.
        // 120 is an initialized tick for this pool. We check that we don't count it.
        IV4QuoterV2.QuoteExactParams memory params = getExactInputParams(tokenPath, 6250);

        (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactInput(params);

        vm.snapshotGasLastCall("QuoterV2_quoteExactInput_oneHop_initializedAfter");

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountOut, 6190);
    }

    function testQuoterV2_quoteExactInput_2to0_0TickLoaded_startingInitialized() public {
        setupPoolWithZeroTickInitialized(key02);
        tokenPath.push(token2);
        tokenPath.push(token0);
        IV4QuoterV2.QuoteExactParams memory params = getExactInputParams(tokenPath, 200);

        // Tick 0 initialized. Tick after = 1
        (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactInput(params);

        vm.snapshotGasLastCall("QuoterV2_quoteExactInput_oneHop_startingInitialized");

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountOut, 198);
    }

    // 2->0 starting not initialized
    function testQuoterV2_quoteExactInput_2to0_0TickLoaded_startingNotInitialized() public {
        tokenPath.push(token2);
        tokenPath.push(token0);
        IV4QuoterV2.QuoteExactParams memory params = getExactInputParams(tokenPath, 103);

        (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactInput(params);

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountOut, 101);
    }

    function testQuoterV2_quoteExactInput_2to1() public {
        tokenPath.push(token2);
        tokenPath.push(token1);
        IV4QuoterV2.QuoteExactParams memory params = getExactInputParams(tokenPath, 10000);

        (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactInput(params);
        
        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountOut, 9871);
    }

    function testQuoterV2_quoteExactInput_0to2to1() public {
        tokenPath.push(token0);
        tokenPath.push(token2);
        tokenPath.push(token1);
        IV4QuoterV2.QuoteExactParams memory params = getExactInputParams(tokenPath, 10000);

        (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactInput(params);

        vm.snapshotGasLastCall("QuoterV2_quoteExactInput_twoHops");

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountOut, 9745);
    }

    function testQuoterV2_quoteExactOutputSingle_0to1() public {
        uint256 amountOut = 10000;
        (uint256 amountIn, uint160 sqrtPriceX96After, int24 tickAfter,) = quoter.quoteExactOutputSingle(
            IV4QuoterV2.QuoteExactSingleParams({
                poolKey: key01,
                zeroForOne: true,
                exactAmount: uint128(amountOut),
                hookData: ZERO_BYTES
            })
        );
        vm.snapshotGasLastCall("QuoterV2_exactOutputSingle_zeroForOne");

        console.log("sqrtPriceX96After:", sqrtPriceX96After);
        console.log("tickAfter:", tickAfter);
        assertEq(amountIn, 10133);
    }

    function testQuoterV2_quoteExactOutputSingle_1to0() public {
        uint256 amountOut = 10000;
        (uint256 amountIn, uint160 sqrtPriceX96After, int24 tickAfter,) = quoter.quoteExactOutputSingle(
            IV4QuoterV2.QuoteExactSingleParams({
                poolKey: key01,
                zeroForOne: false,
                exactAmount: uint128(amountOut),
                hookData: ZERO_BYTES
            })
        );
        vm.snapshotGasLastCall("QuoterV2_exactOutputSingle_oneForZero");

        console.log("sqrtPriceX96After:", sqrtPriceX96After);
        console.log("tickAfter:", tickAfter);
        assertEq(amountIn, 10133);
    }

    function testQuoterV2_quoteExactOutput_0to2_2TicksLoaded() public {
        tokenPath.push(token0);
        tokenPath.push(token2);
        IV4QuoterV2.QuoteExactParams memory params = getExactOutputParams(tokenPath, 15000);

        (uint256 amountIn, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactOutput(params);

        vm.snapshotGasLastCall("QuoterV2_quoteExactOutput_oneHop_2TicksLoaded");
        
        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountIn, 15273);
    }

    function testQuoterV2_quoteExactOutput_0to2_1TickLoaded_initializedAfter() public {
        tokenPath.push(token0);
        tokenPath.push(token2);

        IV4QuoterV2.QuoteExactParams memory params = getExactOutputParams(tokenPath, 6143);

        (uint256 amountIn, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactOutput(params);

        vm.snapshotGasLastCall("QuoterV2_quoteExactOutput_oneHop_initializedAfter");
        
        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountIn, 6200);
    }

    function testQuoterV2_quoteExactOutput_0to2_1TickLoaded() public {
        tokenPath.push(token0);
        tokenPath.push(token2);

        IV4QuoterV2.QuoteExactParams memory params = getExactOutputParams(tokenPath, 4000);

        (uint256 amountIn, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactOutput(params);

        vm.snapshotGasLastCall("QuoterV2_quoteExactOutput_oneHop_1TickLoaded");
        
        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountIn, 4029);
    }

    function testQuoterV2_quoteExactOutput_0to2_0TickLoaded_startingInitialized() public {
        setupPoolWithZeroTickInitialized(key02);
        tokenPath.push(token0);
        tokenPath.push(token2);

        IV4QuoterV2.QuoteExactParams memory params = getExactOutputParams(tokenPath, 100);

        // Tick 0 initialized. Tick after = 1
        (uint256 amountIn, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactOutput(params);
        vm.snapshotGasLastCall("QuoterV2_quoteExactOutput_oneHop_startingInitialized");

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountIn, 102);
    }

    function testQuoterV2_quoteExactOutput_0to2_0TickLoaded_startingNotInitialized() public {
        tokenPath.push(token0);
        tokenPath.push(token2);

        IV4QuoterV2.QuoteExactParams memory params = getExactOutputParams(tokenPath, 10);

        (uint256 amountIn, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactOutput(params);

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountIn, 12);
    }

    function testQuoterV2_quoteExactOutput_2to0_2TicksLoaded() public {
        tokenPath.push(token2);
        tokenPath.push(token0);
        IV4QuoterV2.QuoteExactParams memory params = getExactOutputParams(tokenPath, 15000);

        (uint256 amountIn, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactOutput(params);

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountIn, 15273);
    }

    function testQuoterV2_quoteExactOutput_2to0_2TicksLoaded_initializedAfter() public {
        tokenPath.push(token2);
        tokenPath.push(token0);

        IV4QuoterV2.QuoteExactParams memory params = getExactOutputParams(tokenPath, 6223);

        (uint256 amountIn, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactOutput(params);

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountIn, 6283);
    }

    function testQuoterV2_quoteExactOutput_2to0_1TickLoaded() public {
        tokenPath.push(token2);
        tokenPath.push(token0);

        IV4QuoterV2.QuoteExactParams memory params = getExactOutputParams(tokenPath, 6000);
        (uint256 amountIn, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactOutput(params);

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountIn, 6055);
    }

    function testQuoterV2_quoteExactOutput_2to1() public {
        tokenPath.push(token2);
        tokenPath.push(token1);

        IV4QuoterV2.QuoteExactParams memory params = getExactOutputParams(tokenPath, 9871);

        (uint256 amountIn, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactOutput(params);

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountIn, 10000);
    }

    function testQuoterV2_quoteExactOutput_0to2to1() public {
        tokenPath.push(token0);
        tokenPath.push(token2);
        tokenPath.push(token1);

        IV4QuoterV2.QuoteExactParams memory params = getExactOutputParams(tokenPath, 9745);

        (uint256 amountIn, uint160[] memory sqrtPriceX96AfterList, int24[] memory tickAfterList,) = quoter.quoteExactOutput(params);

        vm.snapshotGasLastCall("QuoterV2_quoteExactOutput_twoHops");

        console.log("sqrtPriceX96AfterList length:", sqrtPriceX96AfterList.length);
        console.log("tickAfterList length:", tickAfterList.length);
        for (uint256 i = 0; i < sqrtPriceX96AfterList.length; i++) {
            console.log("sqrtPriceX96AfterList[", i, "]:", sqrtPriceX96AfterList[i]);
            console.log("tickAfterList[", i, "]:");
            console.log(int256(tickAfterList[i]));
        }
        assertEq(amountIn, 10000);
    }

    function test_fuzz_quoterV2_msgSender(address pranker, bool zeroForOne, bool exactInput) public {
        IV4QuoterV2.QuoteExactSingleParams memory params = IV4QuoterV2.QuoteExactSingleParams({
            poolKey: key01Hook,
            zeroForOne: zeroForOne,
            exactAmount: 10000,
            hookData: ZERO_BYTES
        });

        vm.expectEmit(true, true, true, true);
        emit MockMsgSenderHook.BeforeSwapMsgSender(pranker);

        vm.expectEmit(true, true, true, true);
        emit MockMsgSenderHook.AfterSwapMsgSender(pranker);

        vm.prank(pranker);
        if (exactInput) {
            quoter.quoteExactInputSingle(params);
        } else {
            quoter.quoteExactOutputSingle(params);
        }
    }

    function createPoolKey(MockERC20 tokenA, MockERC20 tokenB, address hookAddr)
        internal
        pure
        returns (PoolKey memory)
    {
        if (address(tokenA) > address(tokenB)) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey(Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)), 3000, 60, IHooks(hookAddr));
    }

    function setupPool(PoolKey memory poolKey) internal {
        manager.initialize(poolKey, SQRT_PRICE_1_1);
        MockERC20(Currency.unwrap(poolKey.currency0)).approve(address(positionManager), type(uint256).max);
        MockERC20(Currency.unwrap(poolKey.currency1)).approve(address(positionManager), type(uint256).max);
        positionManager.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams(
                MIN_TICK,
                MAX_TICK,
                calculateLiquidityFromAmounts(SQRT_PRICE_1_1, MIN_TICK, MAX_TICK, 1000000, 1000000).toInt256(),
                0
            ),
            ZERO_BYTES
        );
    }

    function setupPoolMultiplePositions(PoolKey memory poolKey) internal {
        manager.initialize(poolKey, SQRT_PRICE_1_1);
        MockERC20(Currency.unwrap(poolKey.currency0)).approve(address(positionManager), type(uint256).max);
        MockERC20(Currency.unwrap(poolKey.currency1)).approve(address(positionManager), type(uint256).max);
        positionManager.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams(
                MIN_TICK,
                MAX_TICK,
                calculateLiquidityFromAmounts(SQRT_PRICE_1_1, MIN_TICK, MAX_TICK, 1000000, 1000000).toInt256(),
                0
            ),
            ZERO_BYTES
        );
        positionManager.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams(
                -60, 60, calculateLiquidityFromAmounts(SQRT_PRICE_1_1, -60, 60, 100, 100).toInt256(), 0
            ),
            ZERO_BYTES
        );
        positionManager.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams(
                -120, 120, calculateLiquidityFromAmounts(SQRT_PRICE_1_1, -120, 120, 100, 100).toInt256(), 0
            ),
            ZERO_BYTES
        );
    }

    function setupPoolWithZeroTickInitialized(PoolKey memory poolKey) internal {
        PoolId poolId = poolKey.toId();
        (uint160 sqrtPriceX96,,,) = manager.getSlot0(poolId);
        if (sqrtPriceX96 == 0) {
            manager.initialize(poolKey, SQRT_PRICE_1_1);
        }

        MockERC20(Currency.unwrap(poolKey.currency0)).approve(address(positionManager), type(uint256).max);
        MockERC20(Currency.unwrap(poolKey.currency1)).approve(address(positionManager), type(uint256).max);
        positionManager.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams(
                MIN_TICK,
                MAX_TICK,
                calculateLiquidityFromAmounts(SQRT_PRICE_1_1, MIN_TICK, MAX_TICK, 1000000, 1000000).toInt256(),
                0
            ),
            ZERO_BYTES
        );
        positionManager.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams(0, 60, calculateLiquidityFromAmounts(SQRT_PRICE_1_1, 0, 60, 100, 100).toInt256(), 0),
            ZERO_BYTES
        );
        positionManager.modifyLiquidity(
            poolKey,
            ModifyLiquidityParams(
                -120, 0, calculateLiquidityFromAmounts(SQRT_PRICE_1_1, -120, 0, 100, 100).toInt256(), 0
            ),
            ZERO_BYTES
        );
    }

    function calculateLiquidityFromAmounts(
        uint160 sqrtRatioX96,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0,
        uint256 amount1
    ) internal pure returns (uint128 liquidity) {
        uint160 sqrtRatioAX96 = TickMath.getSqrtPriceAtTick(tickLower);
        uint160 sqrtRatioBX96 = TickMath.getSqrtPriceAtTick(tickUpper);
        liquidity =
            LiquidityAmounts.getLiquidityForAmounts(sqrtRatioX96, sqrtRatioAX96, sqrtRatioBX96, amount0, amount1);
    }

    function getExactInputParams(MockERC20[] memory _tokenPath, uint256 amountIn)
        internal
        pure
        returns (IV4QuoterV2.QuoteExactParams memory params)
    {
        PathKey[] memory path = new PathKey[](_tokenPath.length - 1);
        for (uint256 i = 0; i < _tokenPath.length - 1; i++) {
            path[i] = PathKey(Currency.wrap(address(_tokenPath[i + 1])), 3000, 60, IHooks(address(0)), bytes(""));
        }

        params.exactCurrency = Currency.wrap(address(_tokenPath[0]));
        params.path = path;
        params.exactAmount = uint128(amountIn);
    }

    function getExactOutputParams(MockERC20[] memory _tokenPath, uint256 amountOut)
        internal
        pure
        returns (IV4QuoterV2.QuoteExactParams memory params)
    {
        PathKey[] memory path = new PathKey[](_tokenPath.length - 1);
        for (uint256 i = _tokenPath.length - 1; i > 0; i--) {
            path[i - 1] = PathKey(Currency.wrap(address(_tokenPath[i - 1])), 3000, 60, IHooks(address(0)), bytes(""));
        }

        params.exactCurrency = Currency.wrap(address(_tokenPath[_tokenPath.length - 1]));
        params.path = path;
        params.exactAmount = uint128(amountOut);
    }
} 