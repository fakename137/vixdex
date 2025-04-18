// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;
import {Test,console} from "forge-std/Test.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {CurrencySettler} from "@uniswap/v4-core/test/utils/CurrencySettler.sol";
import {SortTokens} from "@uniswap/v4-core/test/utils/SortTokens.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import { IPoolManager } from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {Vix} from "../src/Vix.sol";
contract VixTest is Test,Deployers {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Vix hook;
    address public baseToken;
    address public deriveAsset;
    address[2] ivTokenAdd;
    uint160 _volume = 898;
    struct HookData{
        address deriveAsset;
        uint160 volume;
    }

    function setUp()external {
        deployFreshManagerAndRouters();
        (currency0, currency1) = deployMintAndApprove2Currencies();   
        console.log("_baseTokenCurrency: ",Currency.unwrap(currency0));
        baseToken = address(Currency.unwrap(currency0));
        deriveAsset = address(Currency.unwrap(currency1));
        address hookAddress = address(
            uint160(
                    Hooks.BEFORE_ADD_LIQUIDITY_FLAG |
                    Hooks.BEFORE_SWAP_FLAG |
                    Hooks.BEFORE_SWAP_RETURNS_DELTA_FLAG |
                    Hooks.AFTER_SWAP_FLAG
            )
        );
        deployCodeTo("Vix.sol",abi.encode(manager,baseToken),hookAddress);

        hook = Vix(hookAddress);
        uint256 pairDeadline =(3600*24);

        uint160 tickLiquidity = 13401+4761696;
        uint160 fee = 0.003 * 1000;
        (address[2] memory ivTokenAddresses) = hook.deploy2Currency(deriveAsset,["HIGH-IV-BTC","LOW-IV-BTC"],["HIVB","LIVB"],address(0xCBCdF9626bC03E24f779434178A73a0B4bad62eD),_volume,pairDeadline);
        ivTokenAdd = ivTokenAddresses;
        assertEq(MockERC20(ivTokenAdd[0]).balanceOf(address(manager)), MockERC20(ivTokenAdd[0]).totalSupply());
        assertEq(MockERC20(ivTokenAdd[1]).balanceOf(address(manager)), MockERC20(ivTokenAdd[1]).totalSupply());
        console.log("vix token 0 address",ivTokenAdd[0]);
        console.log("vix token 1 address",ivTokenAdd[1]);
        uint token0ClaimID = CurrencyLibrary.toId(Currency.wrap(ivTokenAdd[0]));
        uint token1ClaimID = CurrencyLibrary.toId(Currency.wrap(ivTokenAdd[1]));

        uint token0ClaimsBalance = manager.balanceOf(
            address(hook),
            token0ClaimID
        );
        uint token1ClaimsBalance = manager.balanceOf(
            address(hook),
            token1ClaimID
        );

        console.log("token0 claims balance: ",token0ClaimsBalance);
        console.log("token1 claims balance: ",token1ClaimsBalance);
        console.log("hook address: ",address(hook));

    }

    function test_swapHighVolatileToken_ExactIn() public{
        //vm.skip(true);
       
        Currency token0;
        Currency token1;

        (token0,token1) = SortTokens.sort(MockERC20(baseToken),MockERC20(ivTokenAdd[0]));
        //initializing Pool for base token & high IV token

        (key, ) = initPool(
            token0,
            token1, //high IV token
            hook,
            3000,
            SQRT_PRICE_1_1
        );
     
        //swap
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
        takeClaims: false,
        settleUsingBurn: false
        });
        console.log("balanceOf high vix token before swap:",MockERC20(ivTokenAdd[0]).balanceOf(address(this)));
   
        bytes memory hookData =  abi.encode(HookData(deriveAsset, _volume));

        swapRouter.swap(
            key,
            IPoolManager.SwapParams(
            {
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }
            ), 
            settings,
            hookData
        );
          (address vixHighToken,address _vixLowToken,uint _circulation0,uint _circulation1,uint _contractHoldings0,uint _contractHoldings1,uint _reserve0,uint _reserve1,address _poolAddress) =hook.getVixData(deriveAsset);
          console.log("circulation0: ",_circulation0);
          console.log("reserve0: ",_reserve0);
          console.log("contractHoldings0: ",_contractHoldings0);
          console.log("balanceOf high vix after swap:",MockERC20(ivTokenAdd[0]).balanceOf(address(this)));

        uint balance = MockERC20(ivTokenAdd[0]).balanceOf(address(this));
        uint halfVixToken = MockERC20(ivTokenAdd[0]).balanceOf(address(this));
        MockERC20(ivTokenAdd[0]).approve(address(swapRouter),halfVixToken);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(
            {
                zeroForOne:false,
                amountSpecified: -int(halfVixToken),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            settings,
            hookData
        );

        console.log("balanceOf high vix after sold:",MockERC20(ivTokenAdd[0]).balanceOf(address(this)));


    }

    function test_swapHighVolatileToken_ExactOut() external{
        //    vm.skip(true);
        Currency token0;
        Currency token1;

        (token0,token1) = SortTokens.sort(MockERC20(baseToken),MockERC20(ivTokenAdd[0]));
        //initializing Pool for base token & high IV token
        (key, ) = initPool(
            token0,
            token1, //high IV token
            hook,
            3000,
            SQRT_PRICE_1_1
        );

        //swap
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
        takeClaims: false,
        settleUsingBurn: false
        });
        console.log("balanceOf high vix token before swap in exact out:",MockERC20(ivTokenAdd[0]).balanceOf(address(this)));
        bytes memory hookData =  abi.encode(HookData(deriveAsset, _volume));

        swapRouter.swap(
            key,
            IPoolManager.SwapParams(
            {
            zeroForOne: true,
            amountSpecified: 166665 * 1 ether,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }
            ), 
            settings,
            hookData
        );
        console.log("balanceOf high vix token after swap in exact out:",MockERC20(ivTokenAdd[0]).balanceOf(address(this)));
        uint balance = MockERC20(ivTokenAdd[0]).balanceOf(address(this));

        MockERC20(ivTokenAdd[0]).approve(address(swapRouter),uint(balance));
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(
            {
                zeroForOne:false,
                amountSpecified: 0.9 ether, //base token oneForZero means vix/eth 
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            settings,
            hookData
        );

        console.log("balanceOf high vix after sold:",MockERC20(ivTokenAdd[0]).balanceOf(address(this)));
    }

    function test_swapLowVolatileToken_ExactIn() external{
        //vm.skip(true);
        Currency token0;
        Currency token1;

        (token0,token1) = SortTokens.sort(MockERC20(baseToken),MockERC20(ivTokenAdd[1]));
        //initializing Pool for base token & low IV token
        (key, ) = initPool(
            token0,
            token1, //low IV token
            hook,
            3000,
            SQRT_PRICE_1_1
        );

        //swap
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
        takeClaims: false,
        settleUsingBurn: false
        });
        console.log("balanceOf low vix token before swap:",MockERC20(ivTokenAdd[1]).balanceOf(address(this)));
        bytes memory hookData =   abi.encode(HookData(deriveAsset, _volume));

        swapRouter.swap(
            key,
            IPoolManager.SwapParams(
            {
            zeroForOne: true,
            amountSpecified: -1 ether,
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
            }
            ), 
            settings,
            hookData
        );
        console.log("balanceOf low vix token after swap:",MockERC20(ivTokenAdd[1]).balanceOf(address(this)));

        uint balance = MockERC20(ivTokenAdd[1]).balanceOf(address(this));
        //uint halfVixToken = MockERC20(ivTokenAdd[1]).balanceOf(address(this));
        MockERC20(ivTokenAdd[1]).approve(address(swapRouter),balance);
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(
            {
                zeroForOne:false,
                amountSpecified: -int(balance),
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            settings,
            hookData
        );

        console.log("balanceOf vix1 after:",MockERC20(ivTokenAdd[1]).balanceOf(address(this)));

    }

    function test_swapLowVolatileToken_ExactOut() external{
        //vm.skip(true);
        Currency token0;
        Currency token1;

        (token0,token1) = SortTokens.sort(MockERC20(baseToken),MockERC20(ivTokenAdd[1]));
        //initializing Pool for base token & low IV token
        (key, ) = initPool(
            token0,
            token1, //low IV token
            hook,
            3000,
            SQRT_PRICE_1_1
        );

        //swap
        PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
        takeClaims: false,
        settleUsingBurn: false
        });
        console.log("balanceOf low vix token before in exact out:",MockERC20(ivTokenAdd[1]).balanceOf(address(this)));
        bytes memory hookData = abi.encode(HookData(deriveAsset, _volume));

        swapRouter.swap(
            key,
            IPoolManager.SwapParams(
            {
            zeroForOne: true,
            amountSpecified: 166665 * 1 ether,
            sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }
            ), 
            settings,
            hookData
        );
        console.log("balanceOf low vix token after swap in exact out:",MockERC20(ivTokenAdd[1]).balanceOf(address(this)));
        
      
         uint balance = MockERC20(ivTokenAdd[1]).balanceOf(address(this));

        MockERC20(ivTokenAdd[1]).approve(address(swapRouter),uint(balance));
        swapRouter.swap(
            key,
            IPoolManager.SwapParams(
            {
                zeroForOne:false,
                amountSpecified: 1 ether, //base token oneForZero means vix/eth 
                sqrtPriceLimitX96: TickMath.MAX_SQRT_PRICE - 1
            }),
            settings,
            hookData
        );

        console.log("balanceOf low vix token after sold:",MockERC20(ivTokenAdd[1]).balanceOf(address(this)));
    
    }

function test_PriceChangesInVolatility() external {
    // Setting up low volatility token
    Currency lowToken0;
    Currency lowToken1;

    (lowToken0, lowToken1) = SortTokens.sort(MockERC20(baseToken), MockERC20(ivTokenAdd[1]));
    (key, ) = initPool(lowToken0, lowToken1, hook, 3000, SQRT_PRICE_1_1);

    // Swap settings
    PoolSwapTest.TestSettings memory settings = PoolSwapTest.TestSettings({
        takeClaims: false,
        settleUsingBurn: false
    });

    bytes memory hookData = abi.encode(HookData(deriveAsset, _volume));

    // Buying low IV/VIX token
    swapRouter.swap(
        key,
        IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -2 ether, 
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        }),
        settings,
        hookData
    );

    // Setting up high volatility token
    Currency highToken0;
    Currency highToken1;

    (highToken0, highToken1) = SortTokens.sort(MockERC20(baseToken), MockERC20(ivTokenAdd[0]));
    (key, ) = initPool(highToken0, highToken1, hook, 3000, SQRT_PRICE_1_1);

    // Buying high IV/VIX token
    swapRouter.swap(
        key,
        IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -1 ether, 
            sqrtPriceLimitX96: TickMath.MIN_SQRT_PRICE + 1
        }),
        settings,
        hookData
    );

    // Logging token balances
    console.log("Low VIX token balance:", MockERC20(ivTokenAdd[1]).balanceOf(address(this)));
    console.log("High VIX token balance:", MockERC20(ivTokenAdd[0]).balanceOf(address(this)));

    // Fetching VIX token data
    (
        address vixHighToken, 
        address vixLowToken, 
        uint circulation0, 
        uint circulation1, 
        uint contractHoldings0, 
        uint contractHoldings1, 
        uint reserve0, 
        uint reserve1, 
        address poolAddress
    ) = hook.getVixData(deriveAsset);

    // Logging reserves and circulation data
    console.log("Reserve0:", reserve0);
    console.log("Reserve1:", reserve1);
    console.log("Contract Holdings0:", contractHoldings0);
    console.log("Circulation0:", circulation0);
    console.log("Contract Holdings1:", contractHoldings1);
    console.log("Circulation1:", circulation1);
    console.log("price of HVT before volatility shift: ", hook.vixTokensPrice(contractHoldings0));
    console.log("price of LVT before volatility shift: ", hook.vixTokensPrice(contractHoldings1));
    // Swapping reserve based on volatility shift
    (uint reserveShift, uint tokenBurn) = hook.swapReserve(
        20930878980, 21930878980, 
        reserve0, reserve1, 
        circulation0, circulation1, 
        deriveAsset
    );

    // Logging swap results
    console.log("Reserve Shift:", reserveShift);
    console.log("Token Burn:", tokenBurn);

    // Fetching and logging updated price and IV
    uint price = hook.vixTokensPrice(166670 * 1e18);
    uint160 volume = 3590;
    uint iv = hook.calculateIv(0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8, volume);
    console.log("IV:", iv);
    console.log("Price:", price);

    // Fetching updated VIX token data after swap
    (
        vixHighToken, 
        vixLowToken, 
        circulation0, 
        circulation1, 
        contractHoldings0, 
        contractHoldings1, 
        reserve0, 
        reserve1, 
        poolAddress
    ) = hook.getVixData(deriveAsset);

    // Logging updated reserves and circulation data
    console.log("Updated Reserve0:", reserve0);
    console.log("Updated Reserve1:", reserve1);
    console.log("Updated Contract Holdings0:", contractHoldings0);
    console.log("Updated Circulation0:", circulation0);
    console.log("Updated Contract Holdings1:", contractHoldings1);
    console.log("Updated Circulation1:", circulation1);
    console.log("price of HVT before volatility shift: ", hook.vixTokensPrice(contractHoldings0));
    console.log("price of LVT before volatility shift: ", hook.vixTokensPrice(contractHoldings1));
}


    function test_resetPair() external{
        //expect revert when trying to reset pair before deadline
        uint deadline = 3600 * 24;
        console.log("block timestamp: ",block.timestamp);
        vm.expectRevert();
        hook.resetPair(deriveAsset, deadline,0xCBCdF9626bC03E24f779434178A73a0B4bad62eD,_volume);
        //expect revert when transfering token after deadline
        vm.warp(block.timestamp + 30 hours);
        console.log("block timestamp: ",block.timestamp);
        hook.resetPair(deriveAsset, deadline,0xCBCdF9626bC03E24f779434178A73a0B4bad62eD,_volume); 
    }
    
    

}


/*

Limitations:
    1. ETH should be in token1 for the liquidity conversion to work correctly.(because it is static right now)
    12122106024
 */


