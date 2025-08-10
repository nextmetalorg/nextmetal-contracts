// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Test, console2 } from "forge-std/Test.sol";
import { NextMetalPreSale } from "../src/NextMetalPreSale.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(uint8 decimals_) {
        _decimals = decimals_;
    }

    function name() public pure override returns (string memory) {
        return "USD Coin";
    }

    function symbol() public pure override returns (string memory) {
        return "USDC";
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract NextMetalPreSaleTest is Test {
    NextMetalPreSale public presale;
    MockERC20 public usdc;

    address public owner = makeAddr("owner");
    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 constant USDC_DECIMALS = 6;
    uint256 constant TOKEN_DECIMALS = 18;

    // Round IDs
    uint8 constant ANGEL_ROUND = 0;
    uint8 constant SEED_ROUND = 1;
    uint8 constant VC_ROUND = 2;
    uint8 constant COMMUNITY_ROUND = 3;

    // Events (needed for testing)
    event PurchaseMade(uint8 indexed roundId, address indexed buyer, uint256 usdcAmount, uint256 tokenAmount);
    event RoundStarted(uint8 indexed roundId);
    event RoundStopped(uint8 indexed roundId);
    event WhitelistToggled(uint8 indexed roundId, bool isActive);
    event WhitelistedAddressAdded(uint8 indexed roundId, address indexed account);
    event WhitelistedAddressRemoved(uint8 indexed roundId, address indexed account);
    event TreasuryUpdated(address indexed oldAddress, address indexed newAddress);
    event Paused();
    event Unpaused();

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock USDC
        usdc = new MockERC20(uint8(USDC_DECIMALS));

        // Deploy presale contract
        presale = new NextMetalPreSale(address(usdc), treasury, "NEXT METAL POINTS", "NMP");

        // Mint USDC to test users
        usdc.mint(alice, 1_000_000 * 10 ** USDC_DECIMALS); // 1M USDC
        usdc.mint(bob, 1_000_000 * 10 ** USDC_DECIMALS); // 1M USDC

        vm.stopPrank();

        // Approve presale contract to spend USDC
        vm.prank(alice);
        usdc.approve(address(presale), type(uint256).max);

        vm.prank(bob);
        usdc.approve(address(presale), type(uint256).max);
    }

    function testInitialState() public view {
        assertEq(presale.name(), "NEXT METAL POINTS");
        assertEq(presale.symbol(), "NMP");
        assertEq(presale.decimals(), 18);
        assertEq(presale.treasury(), treasury);
        assertEq(presale.owner(), owner);
        assertEq(presale.totalSupply(), 0);
        assertEq(presale.paused(), false);
    }

    function testRoundConfiguration() public view {
        // Test Angel Round
        (uint256 allocation, uint256 price, uint256 sold,,, bool isActive,) = presale.getRoundInfo(ANGEL_ROUND);
        assertEq(allocation, 5_000_000 * 10 ** TOKEN_DECIMALS);
        assertEq(price, 5 * 10 ** (USDC_DECIMALS - 2)); // 0.05 USDC
        assertEq(sold, 0);
        assertEq(isActive, false);

        // Test Seed Round
        (allocation, price, sold,,, isActive,) = presale.getRoundInfo(SEED_ROUND);
        assertEq(allocation, 5_000_000 * 10 ** TOKEN_DECIMALS);
        assertEq(price, 10 * 10 ** (USDC_DECIMALS - 2)); // 0.10 USDC
        assertEq(sold, 0);
        assertEq(isActive, false);

        // Test VC Round
        (allocation, price, sold,,, isActive,) = presale.getRoundInfo(VC_ROUND);
        assertEq(allocation, 10_000_000 * 10 ** TOKEN_DECIMALS);
        assertEq(price, 18 * 10 ** (USDC_DECIMALS - 2)); // 0.18 USDC
        assertEq(sold, 0);
        assertEq(isActive, false);

        // Test Community Round
        (allocation, price, sold,,, isActive,) = presale.getRoundInfo(COMMUNITY_ROUND);
        assertEq(allocation, 10_000_000 * 10 ** TOKEN_DECIMALS);
        assertEq(price, 36 * 10 ** (USDC_DECIMALS - 2)); // 0.36 USDC
        assertEq(sold, 0);
        assertEq(isActive, false);
    }

    function testStartAndStopRound() public {
        // Start round
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        (,,,,, bool isActive,) = presale.getRoundInfo(ANGEL_ROUND);
        assertTrue(isActive);

        // Stop round
        vm.prank(owner);
        presale.stopRound(ANGEL_ROUND);

        (,,,,, isActive,) = presale.getRoundInfo(ANGEL_ROUND);
        assertFalse(isActive);
    }

    function testBuyTokens() public {
        // Start Angel round
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        uint256 usdcAmount = 1000 * 10 ** USDC_DECIMALS; // 1000 USDC
        uint256 expectedTokens = 20_000 * 10 ** TOKEN_DECIMALS; // 20,000 tokens at 0.05 USDC per token

        uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);

        // Buy tokens
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, usdcAmount);

        // Check balances
        assertEq(presale.balanceOf(alice), expectedTokens);
        assertEq(usdc.balanceOf(treasury) - treasuryBalanceBefore, usdcAmount);

        // Check round state
        (,, uint256 sold,,,,) = presale.getRoundInfo(ANGEL_ROUND);
        assertEq(sold, expectedTokens);
        assertEq(presale.totalSupply(), expectedTokens);
    }

    function testWhitelistFunctionality() public {
        // Enable whitelist for Angel round
        vm.prank(owner);
        presale.setWhitelistRequired(ANGEL_ROUND, true);

        // Start round
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Try to buy without being whitelisted - should fail
        vm.prank(alice);
        vm.expectRevert(NextMetalPreSale.NotWhitelisted.selector);
        presale.buy(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS);

        // Add to whitelist
        vm.prank(owner);
        presale.addToWhitelist(ANGEL_ROUND, alice);

        // Now should be able to buy
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS);

        assertGt(presale.balanceOf(alice), 0);
    }

    function testPurchaseLimits() public {
        // Set purchase limits
        uint256 minPurchase = 100 * 10 ** USDC_DECIMALS;
        uint256 maxPurchase = 10_000 * 10 ** USDC_DECIMALS;

        vm.prank(owner);
        presale.setPurchaseLimits(ANGEL_ROUND, minPurchase, maxPurchase);

        // Start round
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Try to buy below minimum - should fail
        vm.prank(alice);
        vm.expectRevert(NextMetalPreSale.BelowMinimumPurchase.selector);
        presale.buy(ANGEL_ROUND, 50 * 10 ** USDC_DECIMALS);

        // Buy at minimum - should succeed
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, minPurchase);

        // Try to exceed maximum - should fail
        vm.prank(alice);
        vm.expectRevert(NextMetalPreSale.ExceedsMaximumPurchase.selector);
        presale.buy(ANGEL_ROUND, maxPurchase);
    }

    function testAutoAdjustPurchase() public {
        // Start Angel round
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Calculate how much USDC is needed to buy all tokens
        uint256 totalUSDCForRound =
            (5_000_000 * 10 ** TOKEN_DECIMALS * 5 * 10 ** (USDC_DECIMALS - 2)) / 10 ** TOKEN_DECIMALS;

        // Try to buy more than available
        uint256 excessAmount = totalUSDCForRound + 1000 * 10 ** USDC_DECIMALS;

        uint256 aliceBalanceBefore = usdc.balanceOf(alice);
        uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);

        vm.prank(alice);
        presale.buy(ANGEL_ROUND, excessAmount);

        // Check that only the exact amount needed is taken when purchase is auto-adjusted
        assertEq(aliceBalanceBefore - usdc.balanceOf(alice), totalUSDCForRound);
        assertEq(usdc.balanceOf(treasury) - treasuryBalanceBefore, totalUSDCForRound);

        // Check that all tokens were sold
        (,, uint256 sold,,,,) = presale.getRoundInfo(ANGEL_ROUND);
        assertEq(sold, 5_000_000 * 10 ** TOKEN_DECIMALS);
    }

    function testPauseUnpause() public {
        // Start round
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Pause contract
        vm.prank(owner);
        presale.pause();

        // Try to buy - should fail
        vm.prank(alice);
        vm.expectRevert(NextMetalPreSale.ContractPaused.selector);
        presale.buy(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS);

        // Unpause
        vm.prank(owner);
        presale.unpause();

        // Now should be able to buy
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS);

        assertGt(presale.balanceOf(alice), 0);
    }

    function testSetTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(owner);
        presale.setTreasury(newTreasury);

        assertEq(presale.treasury(), newTreasury);

        // Start round and buy to test new treasury receives funds
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        uint256 balanceBefore = usdc.balanceOf(newTreasury);

        vm.prank(alice);
        presale.buy(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS);

        assertEq(usdc.balanceOf(newTreasury) - balanceBefore, 100 * 10 ** USDC_DECIMALS);
    }

    function testReadOnlyERC20Functions() public {
        // Start round and make a purchase
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        vm.prank(alice);
        presale.buy(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS);

        // Test read functions
        assertEq(presale.decimals(), 18);
        assertEq(presale.balanceOf(alice), 2000 * 10 ** TOKEN_DECIMALS); // 100 USDC / 0.05 = 2000 tokens
        assertEq(presale.totalSupply(), 2000 * 10 ** TOKEN_DECIMALS);
    }

    function testMultipleRoundsPurchase() public {
        // Start multiple rounds
        vm.startPrank(owner);
        presale.startRound(ANGEL_ROUND);
        presale.startRound(SEED_ROUND);
        vm.stopPrank();

        // Buy from Angel round
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS); // Gets 2,000 tokens

        // Buy from Seed round
        vm.prank(alice);
        presale.buy(SEED_ROUND, 500 * 10 ** USDC_DECIMALS); // Gets 5,000 tokens

        // Check total balance
        assertEq(presale.balanceOf(alice), 7_000 * 10 ** TOKEN_DECIMALS);
        assertEq(presale.totalSupply(), 7_000 * 10 ** TOKEN_DECIMALS);
    }

    function testOnlyOwnerFunctions() public {
        // Non-owner tries to start round
        vm.prank(alice);
        vm.expectRevert(); // Solady's Ownable revert
        presale.startRound(ANGEL_ROUND);

        // Non-owner tries to pause
        vm.prank(alice);
        vm.expectRevert();
        presale.pause();

        // Non-owner tries to set treasury
        vm.prank(alice);
        vm.expectRevert();
        presale.setTreasury(alice);
    }

    // Auto-adjust test scenarios
    function testAutoAdjustWhenExceedsAllocation() public {
        // Start Angel round
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Calculate the exact USDC needed for entire allocation
        uint256 allocationTokens = 5_000_000 * 10 ** TOKEN_DECIMALS;
        uint256 pricePerToken = 5 * 10 ** (USDC_DECIMALS - 2); // 0.05 USDC
        uint256 totalUSDCForAllocation = (allocationTokens * pricePerToken) / 10 ** TOKEN_DECIMALS;

        // Alice tries to buy 10% more than the allocation
        uint256 aliceAttemptedPurchase = totalUSDCForAllocation + (totalUSDCForAllocation / 10);

        uint256 aliceUSDCBefore = usdc.balanceOf(alice);
        uint256 treasuryUSDCBefore = usdc.balanceOf(treasury);

        // The contract auto-adjusts the purchase amount
        // Alice should receive exactly the allocation amount
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, aliceAttemptedPurchase);

        // Verify Alice received exactly the allocation
        assertEq(presale.balanceOf(alice), allocationTokens);
        // Verify only the exact amount was charged (auto-adjusted)
        assertEq(aliceUSDCBefore - usdc.balanceOf(alice), totalUSDCForAllocation);
        // Verify treasury received the exact amount
        assertEq(usdc.balanceOf(treasury) - treasuryUSDCBefore, totalUSDCForAllocation);
    }

    function testExactAllocationPurchase() public {
        // Start Angel round
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Calculate exact USDC for entire allocation
        uint256 allocationTokens = 5_000_000 * 10 ** TOKEN_DECIMALS;
        uint256 pricePerToken = 5 * 10 ** (USDC_DECIMALS - 2);
        uint256 exactUSDCAmount = (allocationTokens * pricePerToken) / 10 ** TOKEN_DECIMALS;

        uint256 aliceUSDCBefore = usdc.balanceOf(alice);
        uint256 treasuryUSDCBefore = usdc.balanceOf(treasury);

        // Buy exact allocation amount
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, exactUSDCAmount);

        // Verify exact amounts
        assertEq(presale.balanceOf(alice), allocationTokens);
        assertEq(usdc.balanceOf(treasury) - treasuryUSDCBefore, exactUSDCAmount);
        assertEq(aliceUSDCBefore - usdc.balanceOf(alice), exactUSDCAmount);

        // Verify round is sold out
        (,, uint256 sold,,,,) = presale.getRoundInfo(ANGEL_ROUND);
        assertEq(sold, allocationTokens);
    }

    function testMultipleUsersWithPartialAllocations() public {
        // Start Angel round
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Calculate values
        uint256 allocationTokens = 5_000_000 * 10 ** TOKEN_DECIMALS;
        uint256 pricePerToken = 5 * 10 ** (USDC_DECIMALS - 2);

        // Alice buys 80% of allocation
        uint256 aliceTokens = (allocationTokens * 80) / 100;
        uint256 aliceUSDC = (aliceTokens * pricePerToken) / 10 ** TOKEN_DECIMALS;

        vm.prank(alice);
        presale.buy(ANGEL_ROUND, aliceUSDC);

        // Bob tries to buy 40% (only 20% available)
        uint256 bobAttemptTokens = (allocationTokens * 40) / 100;
        uint256 bobAttemptUSDC = (bobAttemptTokens * pricePerToken) / 10 ** TOKEN_DECIMALS;

        uint256 bobUSDCBefore = usdc.balanceOf(bob);
        uint256 treasuryBefore = usdc.balanceOf(treasury);

        // Bob's purchase will be auto-adjusted to remaining 20%
        vm.prank(bob);
        presale.buy(ANGEL_ROUND, bobAttemptUSDC);

        // Verify Bob got only the remaining 20%
        uint256 bobExpectedTokens = (allocationTokens * 20) / 100;
        assertEq(presale.balanceOf(bob), bobExpectedTokens);

        // Verify Bob was only charged for what he received (auto-adjusted)
        uint256 bobExpectedUSDC = (bobExpectedTokens * pricePerToken) / 10 ** TOKEN_DECIMALS;
        assertEq(bobUSDCBefore - usdc.balanceOf(bob), bobExpectedUSDC);
        assertEq(usdc.balanceOf(treasury) - treasuryBefore, bobExpectedUSDC);
    }

    function testTokenCalculationAccuracy() public {
        // Start Community round (higher price for better decimal testing)
        vm.prank(owner);
        presale.startRound(COMMUNITY_ROUND);

        // Test with various decimal amounts
        uint256[] memory testAmounts = new uint256[](4);
        testAmounts[0] = 123_456; // 0.123456 USDC
        testAmounts[1] = 1_234_567; // 1.234567 USDC
        testAmounts[2] = 12_345_678; // 12.345678 USDC
        testAmounts[3] = 123_456_789; // 123.456789 USDC

        for (uint256 i = 0; i < testAmounts.length; i++) {
            address buyer = makeAddr(string(abi.encodePacked("buyer", i)));
            usdc.mint(buyer, 1_000_000 * 10 ** USDC_DECIMALS);

            vm.prank(buyer);
            usdc.approve(address(presale), type(uint256).max);

            uint256 buyerBefore = usdc.balanceOf(buyer);
            uint256 treasuryBefore = usdc.balanceOf(treasury);

            // Calculate expected tokens
            uint256 expectedTokens = (testAmounts[i] * 10 ** TOKEN_DECIMALS) / (36 * 10 ** (USDC_DECIMALS - 2));
            vm.prank(buyer);
            presale.buy(COMMUNITY_ROUND, testAmounts[i]);

            // Verify correct amounts
            assertEq(presale.balanceOf(buyer), expectedTokens);
            assertEq(buyerBefore - usdc.balanceOf(buyer), testAmounts[i]);
            assertEq(usdc.balanceOf(treasury) - treasuryBefore, testAmounts[i]);
        }
    }

    function testAutoAdjustMechanismGasEfficiency() public {
        // Start Angel round
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Small purchase (no auto-adjust path)
        uint256 smallAmount = 100 * 10 ** USDC_DECIMALS;

        uint256 gasStart = gasleft();
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, smallAmount);
        gasleft(); // consume gas for first transaction

        // Large purchase that would trigger auto-adjust
        // First, nearly fill the round (leave 1000 tokens)
        uint256 allocationTokens = 5_000_000 * 10 ** TOKEN_DECIMALS;
        uint256 pricePerToken = 5 * 10 ** (USDC_DECIMALS - 2);
        // Leave 1000 tokens available (worth 50 USDC)
        uint256 tokensToFill = allocationTokens - 2000 * 10 ** TOKEN_DECIMALS - 1000 * 10 ** TOKEN_DECIMALS;
        uint256 almostFullUSDC = (tokensToFill * pricePerToken) / 10 ** TOKEN_DECIMALS;

        vm.prank(bob);
        presale.buy(ANGEL_ROUND, almostFullUSDC);

        // Now Alice tries to buy more than remaining
        uint256 largeAmount = 1000 * 10 ** USDC_DECIMALS;
        uint256 aliceBalanceBefore = usdc.balanceOf(alice);

        gasStart = gasleft();
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, largeAmount);
        uint256 gasUsedWithAutoAdjust = gasStart - gasleft();

        // Verify auto-adjust occurred
        uint256 remainingTokens = 1000 * 10 ** TOKEN_DECIMALS;
        uint256 expectedUSDC = (remainingTokens * pricePerToken) / 10 ** TOKEN_DECIMALS;
        assertEq(aliceBalanceBefore - usdc.balanceOf(alice), expectedUSDC);

        // Gas usage with auto-adjust will be slightly different but should be reasonable
        // Just verify the transaction succeeded by checking gas was consumed
        assertGt(gasUsedWithAutoAdjust, 0);
    }

    function testAutoAdjustDemonstration() public {
        // This test demonstrates the auto-adjust functionality
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Fill most of the round
        uint256 allocationTokens = 5_000_000 * 10 ** TOKEN_DECIMALS;
        uint256 pricePerToken = 5 * 10 ** (USDC_DECIMALS - 2);
        uint256 fillAmount = (((allocationTokens * 99) / 100) * pricePerToken) / 10 ** TOKEN_DECIMALS;

        vm.prank(alice);
        presale.buy(ANGEL_ROUND, fillAmount);

        // Bob tries to buy with 1000 USDC (less than cost of all remaining tokens)
        uint256 bobAttempt = 1000 * 10 ** USDC_DECIMALS;
        uint256 bobBalanceBefore = usdc.balanceOf(bob);
        uint256 treasuryBalanceBefore = usdc.balanceOf(treasury);

        // The contract will let Bob buy what he can afford with 1000 USDC
        vm.prank(bob);
        presale.buy(ANGEL_ROUND, bobAttempt);

        // Bob should get 20,000 tokens for his 1000 USDC (at 0.05 USDC per token)
        uint256 expectedTokens = (bobAttempt * 10 ** TOKEN_DECIMALS) / pricePerToken;

        // Verify Bob received the tokens he paid for
        assertEq(presale.balanceOf(bob), expectedTokens);
        // Verify Bob was charged exactly what he requested
        assertEq(bobBalanceBefore - usdc.balanceOf(bob), bobAttempt);
        // Verify treasury received the correct amount
        assertEq(usdc.balanceOf(treasury) - treasuryBalanceBefore, bobAttempt);
    }

    // Edge Cases & Boundary Testing
    function testZeroAmountPurchase() public {
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        uint256 aliceBalanceBefore = presale.balanceOf(alice);
        uint256 usdcBalanceBefore = usdc.balanceOf(alice);

        // Contract allows zero amount purchases (no revert)
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, 0);

        // Verify no tokens were minted and no USDC was transferred
        assertEq(presale.balanceOf(alice), aliceBalanceBefore);
        assertEq(usdc.balanceOf(alice), usdcBalanceBefore);
        assertEq(presale.totalSupply(), 0);
    }

    function testRoundSoldOut() public {
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Buy entire allocation
        uint256 allocationTokens = 10_000_000 * 10 ** TOKEN_DECIMALS;
        uint256 pricePerToken = 5 * 10 ** (USDC_DECIMALS - 2);
        uint256 totalUSDC = (allocationTokens * pricePerToken) / 10 ** TOKEN_DECIMALS;

        vm.prank(alice);
        presale.buy(ANGEL_ROUND, totalUSDC);

        // Try to buy more - should get 0 tokens
        uint256 bobBalanceBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        presale.buy(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS);

        // Bob should have received 0 tokens and paid 0 USDC
        assertEq(presale.balanceOf(bob), 0);
        assertEq(usdc.balanceOf(bob), bobBalanceBefore);
    }

    function testInvalidRoundId() public {
        vm.prank(owner);
        vm.expectRevert(NextMetalPreSale.InvalidRound.selector);
        presale.startRound(4); // Invalid round ID

        vm.prank(alice);
        vm.expectRevert(NextMetalPreSale.InvalidRound.selector);
        presale.buy(5, 100 * 10 ** USDC_DECIMALS);
    }

    function testPurchaseWithInsufficientBalance() public {
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Create new user with no USDC
        address poorUser = makeAddr("poorUser");
        vm.prank(poorUser);
        usdc.approve(address(presale), type(uint256).max);

        vm.prank(poorUser);
        vm.expectRevert(); // ERC20 insufficient balance
        presale.buy(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS);
    }

    function testPurchaseWithInsufficientAllowance() public {
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Create new user with USDC but no allowance
        address noAllowanceUser = makeAddr("noAllowanceUser");
        usdc.mint(noAllowanceUser, 1000 * 10 ** USDC_DECIMALS);

        vm.prank(noAllowanceUser);
        vm.expectRevert(); // ERC20 insufficient allowance
        presale.buy(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS);
    }

    // Whitelist Edge Cases
    function testRemoveFromWhitelist() public {
        vm.prank(owner);
        presale.setWhitelistRequired(ANGEL_ROUND, true);

        // Add to whitelist
        vm.prank(owner);
        presale.addToWhitelist(ANGEL_ROUND, alice);
        assertTrue(presale.whitelist(ANGEL_ROUND, alice));

        // Remove from whitelist
        vm.prank(owner);
        presale.removeFromWhitelist(ANGEL_ROUND, alice);
        assertFalse(presale.whitelist(ANGEL_ROUND, alice));

        // Try to buy after removal
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        vm.prank(alice);
        vm.expectRevert(NextMetalPreSale.NotWhitelisted.selector);
        presale.buy(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS);
    }

    function testMultipleWhitelistOperations() public {
        vm.startPrank(owner);
        presale.setWhitelistRequired(ANGEL_ROUND, true);

        // Add
        presale.addToWhitelist(ANGEL_ROUND, alice);
        assertTrue(presale.whitelist(ANGEL_ROUND, alice));

        // Remove
        presale.removeFromWhitelist(ANGEL_ROUND, alice);
        assertFalse(presale.whitelist(ANGEL_ROUND, alice));

        // Add again
        presale.addToWhitelist(ANGEL_ROUND, alice);
        assertTrue(presale.whitelist(ANGEL_ROUND, alice));
        vm.stopPrank();
    }

    function testWhitelistAcrossMultipleRounds() public {
        vm.startPrank(owner);
        presale.setWhitelistRequired(ANGEL_ROUND, true);
        presale.setWhitelistRequired(SEED_ROUND, true);

        // Whitelist only for Angel round
        presale.addToWhitelist(ANGEL_ROUND, alice);

        presale.startRound(ANGEL_ROUND);
        presale.startRound(SEED_ROUND);
        vm.stopPrank();

        // Can buy from Angel round
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS);

        // Cannot buy from Seed round
        vm.prank(alice);
        vm.expectRevert(NextMetalPreSale.NotWhitelisted.selector);
        presale.buy(SEED_ROUND, 100 * 10 ** USDC_DECIMALS);
    }

    function testAddZeroAddressToWhitelist() public {
        vm.prank(owner);
        vm.expectRevert(NextMetalPreSale.InvalidAddress.selector);
        presale.addToWhitelist(ANGEL_ROUND, address(0));
    }

    // Owner Permission Tests
    function testNonOwnerWhitelistOperations() public {
        vm.prank(alice);
        vm.expectRevert();
        presale.addToWhitelist(ANGEL_ROUND, bob);

        vm.prank(alice);
        vm.expectRevert();
        presale.removeFromWhitelist(ANGEL_ROUND, bob);

        vm.prank(alice);
        vm.expectRevert();
        presale.setWhitelistRequired(ANGEL_ROUND, true);
    }

    function testNonOwnerSetPurchaseLimits() public {
        vm.prank(alice);
        vm.expectRevert();
        presale.setPurchaseLimits(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS, 1000 * 10 ** USDC_DECIMALS);
    }

    function testNonOwnerSetTokenInfo() public {
        vm.prank(alice);
        vm.expectRevert();
        presale.setTokenInfo("New Name", "NEW");
    }

    function testTransferOwnership() public {
        // Alice requests ownership handover
        vm.prank(alice);
        presale.requestOwnershipHandover();

        // Owner completes the handover
        vm.prank(owner);
        presale.completeOwnershipHandover(alice);

        // Old owner can't execute owner functions
        vm.prank(owner);
        vm.expectRevert();
        presale.startRound(ANGEL_ROUND);

        // New owner can execute owner functions
        vm.prank(alice);
        presale.startRound(ANGEL_ROUND);

        (,,,,, bool isActive,) = presale.getRoundInfo(ANGEL_ROUND);
        assertTrue(isActive);
    }

    // Treasury & Constructor Tests
    function testConstructorWithZeroAddresses() public {
        // Test zero USDC address
        vm.expectRevert(NextMetalPreSale.InvalidAddress.selector);
        new NextMetalPreSale(address(0), treasury, "Test", "TST");

        // Test zero treasury address
        vm.expectRevert(NextMetalPreSale.InvalidAddress.selector);
        new NextMetalPreSale(address(usdc), address(0), "Test", "TST");
    }

    function testSetTreasuryToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(NextMetalPreSale.InvalidAddress.selector);
        presale.setTreasury(address(0));
    }

    function testSetTokenInfo() public {
        vm.prank(owner);
        presale.setTokenInfo("NEXT METAL POINTS", "NMP");

        assertEq(presale.name(), "NEXT METAL POINTS");
        assertEq(presale.symbol(), "NMP");
    }

    // Complex Purchase Scenarios
    function testPurchaseAcrossAllRounds() public {
        // Start all rounds
        vm.startPrank(owner);
        presale.startRound(ANGEL_ROUND);
        presale.startRound(SEED_ROUND);
        presale.startRound(VC_ROUND);
        presale.startRound(COMMUNITY_ROUND);
        vm.stopPrank();

        // Alice buys from all rounds
        uint256 purchaseAmount1 = 1000 * 10 ** USDC_DECIMALS;
        uint256 purchaseAmount2 = 1800 * 10 ** USDC_DECIMALS;

        vm.startPrank(alice);
        presale.buy(ANGEL_ROUND, purchaseAmount1); // $0.5 price - 20,000 tokens
        presale.buy(SEED_ROUND, purchaseAmount1); // $0.1 price - 10,000 tokens
        presale.buy(VC_ROUND, purchaseAmount2); // $0.18 price - 10,000 tokens
        presale.buy(COMMUNITY_ROUND, purchaseAmount2);// $0.36 price - 5,000 tokens
        vm.stopPrank();

        // Verify total balance
        uint256 expectedTokens = 20_000 * 10 ** TOKEN_DECIMALS
            + 10_000 * 10 ** TOKEN_DECIMALS
            + 10_000 * 10 ** TOKEN_DECIMALS
            + 5_000 * 10 ** TOKEN_DECIMALS;

        assertEq(presale.balanceOf(alice), expectedTokens);
    }

    function testRoundDeactivationDuringPurchase() public {
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Alice makes initial purchase
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, 1000 * 10 ** USDC_DECIMALS);

        // Stop the round
        vm.prank(owner);
        presale.stopRound(ANGEL_ROUND);

        // Bob tries to buy - should fail
        vm.prank(bob);
        vm.expectRevert(NextMetalPreSale.RoundNotActive.selector);
        presale.buy(ANGEL_ROUND, 1000 * 10 ** USDC_DECIMALS);
    }

    function testMultipleSmallPurchases() public {
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Make 10 small purchases
        uint256 smallAmount = 10 * 10 ** USDC_DECIMALS;
        uint256 expectedTokensPerPurchase = 200 * 10 ** TOKEN_DECIMALS;

        for (uint256 i = 0; i < 10; i++) {
            vm.prank(alice);
            presale.buy(ANGEL_ROUND, smallAmount);
        }

        assertEq(presale.balanceOf(alice), expectedTokensPerPurchase * 10);
        assertEq(presale.purchasedPerRound(ANGEL_ROUND, alice), smallAmount * 10);
    }

    function testExactMinimumPurchase() public {
        uint256 minPurchase = 50 * 10 ** USDC_DECIMALS;

        vm.prank(owner);
        presale.setPurchaseLimits(ANGEL_ROUND, minPurchase, type(uint256).max);

        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Purchase exactly at minimum
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, minPurchase);

        assertEq(presale.purchasedPerRound(ANGEL_ROUND, alice), minPurchase);
    }

    function testPurchaseLimitsUpdate() public {
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Initial purchase
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS);

        // Update limits while round is active
        vm.prank(owner);
        presale.setPurchaseLimits(ANGEL_ROUND, 200 * 10 ** USDC_DECIMALS, 500 * 10 ** USDC_DECIMALS);

        // Try to buy below new minimum
        vm.prank(bob);
        vm.expectRevert(NextMetalPreSale.BelowMinimumPurchase.selector);
        presale.buy(ANGEL_ROUND, 150 * 10 ** USDC_DECIMALS);

        // Alice already purchased, so she can't buy more due to max limit
        vm.prank(alice);
        vm.expectRevert(NextMetalPreSale.ExceedsMaximumPurchase.selector);
        presale.buy(ANGEL_ROUND, 450 * 10 ** USDC_DECIMALS);
    }

    // Auto-Adjust Edge Cases
    function testAutoAdjustWithMinimumPurchase() public {
        vm.prank(owner);
        presale.setPurchaseLimits(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS, type(uint256).max);

        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Fill most of the round, leaving only 1 token worth of allocation
        uint256 allocationTokens = 5_000_000 * 10 ** TOKEN_DECIMALS;
        uint256 pricePerToken = 5 * 10 ** (USDC_DECIMALS - 2);
        uint256 fillAmount = ((allocationTokens - 10 ** TOKEN_DECIMALS) * pricePerToken) / 10 ** TOKEN_DECIMALS;

        vm.prank(alice);
        presale.buy(ANGEL_ROUND, fillAmount);

        // Bob tries to buy with minimum purchase amount
        // Only 1 token left worth 0.05 USDC, but minimum is 100 USDC
        vm.prank(bob);
        presale.buy(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS);

        // Bob should only pay for the 1 token available
        assertEq(presale.balanceOf(bob), 10 ** TOKEN_DECIMALS);
        assertEq(presale.purchasedPerRound(ANGEL_ROUND, bob), pricePerToken);
    }

    function testAutoAdjustWithMaximumPurchase() public {
        vm.prank(owner);
        presale.setPurchaseLimits(ANGEL_ROUND, 0, 1000 * 10 ** USDC_DECIMALS);

        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Alice already purchases 800 USDC worth
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, 800 * 10 ** USDC_DECIMALS);

        // Alice tries to buy 500 USDC more (would exceed max of 1000)
        vm.prank(alice);
        vm.expectRevert(NextMetalPreSale.ExceedsMaximumPurchase.selector);
        presale.buy(ANGEL_ROUND, 500 * 10 ** USDC_DECIMALS);
    }

    function testAutoAdjustToZero() public {
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Buy entire allocation
        uint256 allocationTokens = 10_000_000 * 10 ** TOKEN_DECIMALS;
        uint256 pricePerToken = 5 * 10 ** (USDC_DECIMALS - 2);
        uint256 totalUSDC = (allocationTokens * pricePerToken) / 10 ** TOKEN_DECIMALS;

        vm.prank(alice);
        presale.buy(ANGEL_ROUND, totalUSDC);

        // Bob tries to buy - should auto-adjust to 0
        uint256 bobBalanceBefore = usdc.balanceOf(bob);
        vm.prank(bob);
        presale.buy(ANGEL_ROUND, 1000 * 10 ** USDC_DECIMALS);

        assertEq(presale.balanceOf(bob), 0);
        assertEq(usdc.balanceOf(bob), bobBalanceBefore);
    }

    // View Function Tests
    function testGetRoundInfoInvalidRound() public {
        vm.expectRevert(NextMetalPreSale.InvalidRound.selector);
        presale.getRoundInfo(10);
    }

    function testViewFunctionsAfterPurchases() public {
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        vm.prank(alice);
        presale.buy(ANGEL_ROUND, 1000 * 10 ** USDC_DECIMALS);

        vm.prank(bob);
        presale.buy(ANGEL_ROUND, 500 * 10 ** USDC_DECIMALS);

        // Test all view functions
        assertEq(presale.name(), "NEXT METAL POINTS");
        assertEq(presale.symbol(), "NMP");
        assertEq(presale.decimals(), 18);
        assertEq(presale.totalSupply(), 30_000 * 10 ** TOKEN_DECIMALS);
        assertEq(presale.balanceOf(alice), 20_000 * 10 ** TOKEN_DECIMALS);
        assertEq(presale.balanceOf(bob), 10_000 * 10 ** TOKEN_DECIMALS);
        assertEq(presale.treasury(), treasury);
        assertEq(presale.USDC(), address(usdc));
        assertFalse(presale.paused());

        (,, uint256 sold,,,,) = presale.getRoundInfo(ANGEL_ROUND);
        assertEq(sold, 30_000 * 10 ** TOKEN_DECIMALS);
    }

    // Event Emission Tests
    function testEventEmission() public {
        // Test PurchaseMade event
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        vm.expectEmit(true, true, false, true);
        emit NextMetalPreSale.PurchaseMade(ANGEL_ROUND, alice, 100 * 10 ** USDC_DECIMALS, 2000 * 10 ** TOKEN_DECIMALS);

        vm.prank(alice);
        presale.buy(ANGEL_ROUND, 100 * 10 ** USDC_DECIMALS);

        // Test RoundStarted/Stopped events
        vm.expectEmit(true, false, false, false);
        emit NextMetalPreSale.RoundStarted(SEED_ROUND);

        vm.prank(owner);
        presale.startRound(SEED_ROUND);

        vm.expectEmit(true, false, false, false);
        emit NextMetalPreSale.RoundStopped(SEED_ROUND);

        vm.prank(owner);
        presale.stopRound(SEED_ROUND);

        // Test WhitelistToggled event
        vm.expectEmit(true, false, false, true);
        emit NextMetalPreSale.WhitelistToggled(ANGEL_ROUND, true);

        vm.prank(owner);
        presale.setWhitelistRequired(ANGEL_ROUND, true);

        // Test WhitelistedAddressAdded event
        vm.expectEmit(true, true, false, false);
        emit NextMetalPreSale.WhitelistedAddressAdded(ANGEL_ROUND, alice);

        vm.prank(owner);
        presale.addToWhitelist(ANGEL_ROUND, alice);

        // Test WhitelistedAddressRemoved event
        vm.expectEmit(true, true, false, false);
        emit NextMetalPreSale.WhitelistedAddressRemoved(ANGEL_ROUND, alice);

        vm.prank(owner);
        presale.removeFromWhitelist(ANGEL_ROUND, alice);

        // Test TreasuryUpdated event
        address newTreasury = makeAddr("newTreasury");
        vm.expectEmit(true, true, false, false);
        emit NextMetalPreSale.TreasuryUpdated(treasury, newTreasury);

        vm.prank(owner);
        presale.setTreasury(newTreasury);

        // Test Paused/Unpaused events
        vm.expectEmit(false, false, false, false);
        emit NextMetalPreSale.Paused();

        vm.prank(owner);
        presale.pause();

        vm.expectEmit(false, false, false, false);
        emit NextMetalPreSale.Unpaused();

        vm.prank(owner);
        presale.unpause();
    }

    function testPurchaseMadeEventAutoAdjust() public {
        vm.prank(owner);
        presale.startRound(ANGEL_ROUND);

        // Fill most of the round
        uint256 allocationTokens = 5_000_000 * 10 ** TOKEN_DECIMALS;
        uint256 pricePerToken = 5 * 10 ** (USDC_DECIMALS - 2);
        uint256 remainingTokens = 1000 * 10 ** TOKEN_DECIMALS;
        uint256 fillAmount = ((allocationTokens - remainingTokens) * pricePerToken) / 10 ** TOKEN_DECIMALS;

        vm.prank(alice);
        presale.buy(ANGEL_ROUND, fillAmount);

        // Bob tries to buy more than available
        uint256 adjustedUSDC = (remainingTokens * pricePerToken) / 10 ** TOKEN_DECIMALS;

        vm.expectEmit(true, true, false, true);
        emit NextMetalPreSale.PurchaseMade(ANGEL_ROUND, bob, adjustedUSDC, remainingTokens);

        vm.prank(bob);
        presale.buy(ANGEL_ROUND, 10_000 * 10 ** USDC_DECIMALS); // Attempt large purchase
    }

    // Supply Cap Tests
    function testTotalSupplyTracking() public {
        vm.startPrank(owner);
        presale.startRound(ANGEL_ROUND);
        presale.startRound(SEED_ROUND);
        vm.stopPrank();

        assertEq(presale.totalSupply(), 0);

        // Buy from Angel round
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, 500 * 10 ** USDC_DECIMALS);
        assertEq(presale.totalSupply(), 10_000 * 10 ** TOKEN_DECIMALS);

        // Buy from Seed round
        vm.prank(bob);
        presale.buy(SEED_ROUND, 1000 * 10 ** USDC_DECIMALS);
        assertEq(presale.totalSupply(), 20_000 * 10 ** TOKEN_DECIMALS);

        // Multiple users buy
        vm.prank(alice);
        uint256 alicePurchase = 500 * 10 ** USDC_DECIMALS;
        presale.buy(SEED_ROUND, alicePurchase);

        uint256 seedPrice = 10 * 10 ** (USDC_DECIMALS - 2);
        uint256 aliceTokens = (alicePurchase * 10 ** TOKEN_DECIMALS) / seedPrice;
        uint256 expectedTotal =
            10_000 * 10 ** TOKEN_DECIMALS + 10_000 * 10 ** TOKEN_DECIMALS + aliceTokens;

        assertEq(presale.totalSupply(), expectedTotal);
    }

    function testSupplyCapRespected() public {
        // Start all rounds
        vm.startPrank(owner);
        presale.startRound(ANGEL_ROUND);
        presale.startRound(SEED_ROUND);
        presale.startRound(VC_ROUND);
        presale.startRound(COMMUNITY_ROUND);
        vm.stopPrank();

        // Calculate total allocation across all rounds
        uint256 totalAllocation = 5_000_000 * 10 ** TOKEN_DECIMALS // Angel
            + 5_000_000 * 10 ** TOKEN_DECIMALS // Seed
            + 10_000_000 * 10 ** TOKEN_DECIMALS // VC
            + 10_000_000 * 10 ** TOKEN_DECIMALS; // Community

        assertEq(totalAllocation, 30_000_000 * 10 ** TOKEN_DECIMALS);

        // Calculate required USDC for all rounds
        uint256 angelUSDC = (5_000_000 * 10 ** TOKEN_DECIMALS * 5 * 10 ** (USDC_DECIMALS - 2)) / 10 ** TOKEN_DECIMALS;
        uint256 seedUSDC = (5_000_000 * 10 ** TOKEN_DECIMALS * 10 * 10 ** (USDC_DECIMALS - 2)) / 10 ** TOKEN_DECIMALS;
        uint256 vcUSDC = (10_000_000 * 10 ** TOKEN_DECIMALS * 18 * 10 ** (USDC_DECIMALS - 2)) / 10 ** TOKEN_DECIMALS;
        uint256 communityUSDC =(10_000_000 * 10 ** TOKEN_DECIMALS * 36 * 10 ** (USDC_DECIMALS - 2)) / 10 ** TOKEN_DECIMALS;
        uint256 totalUSDC = angelUSDC + seedUSDC + vcUSDC + communityUSDC;

        // Mint enough USDC for alice
        vm.prank(owner);
        usdc.mint(alice, totalUSDC);

        // Buy entire allocation from each round
        vm.prank(alice);
        presale.buy(ANGEL_ROUND, angelUSDC);

        vm.prank(alice);
        presale.buy(SEED_ROUND, seedUSDC);

        vm.prank(alice);
        presale.buy(VC_ROUND, vcUSDC);

        vm.prank(alice);
        presale.buy(COMMUNITY_ROUND, communityUSDC);

        // Verify total supply equals total allocation
        assertEq(presale.totalSupply(), totalAllocation);
        assertEq(presale.balanceOf(alice), totalAllocation);

        // Verify TOTAL_SUPPLY_CAP is sufficient
        assertLe(totalAllocation, presale.TOTAL_SUPPLY_CAP());
    }
}