// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../../src/core/PonderERC20.sol";
import "../../src/core/PonderFactory.sol";
import "../../src/core/PonderPriceOracle.sol";
import "../../src/core/PonderToken.sol";
import "../../src/launch/FiveFiveFiveLauncher.sol";
import "../../src/launch/LaunchToken.sol";
import "../../src/periphery/PonderRouter.sol";
import "../../test/mocks/WETH9.sol";
import "../mocks/MockKKUBUnwrapper.sol";
import "forge-std/Test.sol";
import "forge-std/console.sol";

contract LaunchSystemTest is Test {
    // Core contracts
    FiveFiveFiveLauncher launcher;
    PonderFactory factory;
    PonderRouter router;
    PonderToken ponder;
    PonderPriceOracle oracle;
    WETH9 weth;

    // Test addresses
    address creator = makeAddr("creator");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address feeCollector = makeAddr("feeCollector");
    address treasury = makeAddr("treasury");
    address teamReserve = makeAddr("teamReserve");
    address marketing = makeAddr("marketing");

    // Protocol constants
    uint256 constant TARGET_RAISE = 5555 ether;
    uint256 constant TOTAL_SUPPLY = 555_555_555 ether;
    uint256 constant UPDATE_INTERVAL = 15 minutes;
    uint256 constant MIN_OBSERVATIONS = 3;

    // Initial liquidity constants
    uint256 constant INITIAL_PONDER = 10_000_000e18;  // 10M PONDER
    uint256 constant INITIAL_WETH = 10_000e18;        // 10K WETH
    uint256 constant LAUNCHER_ETH = 10_000 ether;       // ETH for launcher

    function setUp() public {
        console.log("Starting setup...");
        _setupPhase1();
    }

    function _setupPhase1() private {
        // 1. Initial timestamp setup
        vm.warp(block.timestamp + 30 days);
        console.log("Initial timestamp:", block.timestamp);

        // 2. Deploy core contracts
        console.log("Deploying WETH...");
        weth = new WETH9();

        console.log("Deploying Factory...");
        factory = new PonderFactory(address(this), address(0));

        console.log("Deploying PONDER...");
        ponder = new PonderToken(
            treasury,
            teamReserve,
            marketing,
            address(this)
        );

        // 3. Router setup
        console.log("Setting up Router...");
        MockKKUBUnwrapper unwrapper = new MockKKUBUnwrapper(address(weth));
        router = new PonderRouter(address(factory), address(weth), address(unwrapper));

        _setupPhase2();
    }

    function _setupPhase2() private {
        // 4. Initial token setup
        console.log("Setting up token permissions...");
        vm.startPrank(address(this));
        ponder.setMinter(address(this));

        console.log("Minting initial PONDER:", INITIAL_PONDER);
        ponder.mint(address(this), INITIAL_PONDER);

        console.log("Approving PONDER for router");
        ponder.approve(address(router), INITIAL_PONDER);
        vm.stopPrank();

        // 5. WETH setup
        console.log("Setting up WETH with amount:", INITIAL_WETH);
        vm.deal(address(this), INITIAL_WETH);
        weth.deposit{value: INITIAL_WETH}();
        weth.approve(address(router), INITIAL_WETH);

        _setupPhase3();
    }

    function _setupPhase3() private {
        // 6. Add initial liquidity
        console.log("Adding initial liquidity...");

        // Check balances before adding liquidity
        console.log("PONDER balance:", ponder.balanceOf(address(this)));
        console.log("WETH balance:", weth.balanceOf(address(this)));
        console.log("ETH balance:", address(this).balance);

        router.addLiquidity(
            address(ponder),
            address(weth),
            INITIAL_PONDER,
            INITIAL_WETH,
            0,
            0,
            address(this),
            block.timestamp + 1 hours
        );

        address ponderWethPair = factory.getPair(address(ponder), address(weth));
        require(ponderWethPair != address(0), "Pair not created");
        console.log("Pair created at:", ponderWethPair);

        _setupPhase4(ponderWethPair);
    }

    function _setupPhase4(address ponderWethPair) private {
        // 7. Oracle setup
        console.log("Setting up oracle...");
        oracle = new PonderPriceOracle(address(factory), ponderWethPair);

        // 8. Oracle initialization
        for (uint i = 0; i < MIN_OBSERVATIONS; i++) {
            vm.warp(block.timestamp + UPDATE_INTERVAL);
            vm.roll(block.number + 1);

            if (i > 0) {
                console.log("Making trade for observation", i);
                _makeSmallTrade(i % 2 == 0);
            }

            console.log("Updating oracle observation", i);
            oracle.update(ponderWethPair);
        }

        _setupFinal();
    }

    function _setupFinal() private {
        // 9. Launcher deployment
        console.log("Deploying launcher...");
        launcher = new FiveFiveFiveLauncher(
            address(factory),
            payable(address(router)),
            feeCollector,
            address(ponder),
            address(oracle)
        );

        // 10. Ownership transfer
        console.log("Transferring PONDER ownership...");
        vm.prank(address(this));
        ponder.transferOwnership(address(launcher));

        vm.prank(address(launcher));
        ponder.acceptOwnership();

        // 11. Fund launcher with more ETH
        console.log("Funding launcher with ETH:", LAUNCHER_ETH);
        vm.deal(address(launcher), LAUNCHER_ETH);

        // Verify funding
        require(
            address(launcher).balance >= LAUNCHER_ETH,
            "Launcher ETH funding failed"
        );

        console.log("Launcher ETH balance:", address(launcher).balance);
        console.log("Setup completed successfully");
    }

    function _makeSmallTrade(bool buyPonder) private {
        address[] memory path = new address[](2);
        uint256 amountIn = INITIAL_WETH / 10000; // 0.01% of liquidity

        if (buyPonder) {
            path[0] = address(weth);
            path[1] = address(ponder);
            vm.deal(address(this), amountIn);
            weth.deposit{value: amountIn}();
            weth.approve(address(router), amountIn);
        } else {
            path[0] = address(ponder);
            path[1] = address(weth);
            uint256 ponderAmount = amountIn * (INITIAL_PONDER / INITIAL_WETH);
            ponder.mint(address(this), ponderAmount);
            ponder.approve(address(router), ponderAmount);
            amountIn = ponderAmount;
        }

        console.log("Executing trade, amount:", amountIn);
        router.swapExactTokensForTokens(
            amountIn,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function testCreateLaunch() public {
        vm.startPrank(creator);
        uint256 launchId = launcher.createLaunch(
            "TestToken",
            "TEST",
            "ipfs://test"
        );
        vm.stopPrank();

        (
            address tokenAddress,
            string memory name,
            string memory symbol,
            string memory imageURI,
            uint256 totalRaised,
            bool launched,
            uint256 lpUnlockTime
        ) = launcher.getLaunchInfo(launchId);

        assertEq(name, "TestToken");
        assertEq(symbol, "TEST");
        assertEq(imageURI, "ipfs://test");
        assertEq(totalRaised, 0);
        assertFalse(launched);
        assertEq(lpUnlockTime, 0);
        assertTrue(tokenAddress != address(0));
    }

    function testContributePONDER() public {
        // Create launch
        vm.startPrank(creator);
        uint256 launchId = launcher.createLaunch(
            "TestToken",
            "TEST",
            "ipfs://test"
        );
        vm.stopPrank();

        // Make first contribution - 10% of oracle required amount (~5.555e24)
        uint256 smallAmount = 0.5e24;
        uint256 amountWithBuffer = (smallAmount * 120) / 100; // Add 20% buffer
        console.log("First contribution amount:", smallAmount);
        console.log("Amount with buffer:", amountWithBuffer);

        // Mint tokens with buffer
        ponder.mint(user1, amountWithBuffer);

        vm.startPrank(user1);
        ponder.approve(address(launcher), smallAmount);
        launcher.contribute(launchId, smallAmount);

        // Verify first contribution
        (address tokenAddress,,,,, bool launched,) = launcher.getLaunchInfo(launchId);
        assertFalse(launched, "Launch should not be completed yet");
        assertGt(LaunchToken(tokenAddress).balanceOf(user1), 0, "User1 should have received tokens");
        vm.stopPrank();

        // Second contribution - about 40% of required
        uint256 secondAmount = 2e24;
        uint256 secondWithBuffer = (secondAmount * 120) / 100;
        console.log("Second contribution amount:", secondAmount);

        // Mint for second user with buffer
        ponder.mint(user2, secondWithBuffer);

        vm.startPrank(user2);
        ponder.approve(address(launcher), secondAmount);
        launcher.contribute(launchId, secondAmount);
        vm.stopPrank();

        // Verify state - should still not be launched
        (tokenAddress,,,,, launched,) = launcher.getLaunchInfo(launchId);
        assertFalse(launched, "Launch should not be completed after second contribution");

        // Final contribution to complete launch
        uint256 finalAmount = 3.1e24; // Remainder to complete (~5.555e24 total)
        uint256 finalWithBuffer = (finalAmount * 120) / 100;
        console.log("Final contribution amount:", finalAmount);

        // Mint for final contribution with buffer
        ponder.mint(user2, finalWithBuffer);

        vm.startPrank(user2);
        ponder.approve(address(launcher), finalAmount);
        launcher.contribute(launchId, finalAmount);
        vm.stopPrank();

        // Verify final state
        (tokenAddress,,,,, launched,) = launcher.getLaunchInfo(launchId);
        assertTrue(launched, "Launch should be completed after full contribution");

        // Verify LP
        address pair = factory.getPair(tokenAddress, address(ponder));
        assertTrue(pair != address(0), "LP pair should be created");
        assertGt(PonderERC20(pair).totalSupply(), 0, "LP should have supply");
    }

    function testContributeExcess() public {
        // Create launch
        vm.startPrank(creator);
        uint256 launchId = launcher.createLaunch(
            "TestToken",
            "TEST",
            "ipfs://test"
        );
        vm.stopPrank();

        // Try to contribute 150% of the oracle required amount (~5.555e24)
        uint256 excessAmount = 8e24;
        uint256 amountWithBuffer = (excessAmount * 120) / 100; // Add 20% buffer

        console.log("Attempting to contribute:", excessAmount);
        console.log("Amount with buffer:", amountWithBuffer);

        // Mint tokens with buffer
        ponder.mint(user1, amountWithBuffer);

        uint256 balanceBefore = ponder.balanceOf(user1);

        vm.startPrank(user1);
        ponder.approve(address(launcher), excessAmount);
        launcher.contribute(launchId, excessAmount);

        uint256 balanceAfter = ponder.balanceOf(user1);
        uint256 actualContribution = balanceBefore - balanceAfter;

        console.log("Balance before:", balanceBefore);
        console.log("Balance after:", balanceAfter);
        console.log("Actual contribution:", actualContribution);

        // Verify excess was returned
        assertLt(actualContribution, 6e24, "Should only use up to oracle required");
        assertGt(actualContribution, 5e24, "Should use close to oracle required");

        // Verify launch completed
        (,,,,,bool launched,) = launcher.getLaunchInfo(launchId);
        assertTrue(launched, "Launch should be completed");
        vm.stopPrank();
    }

    function testLPLocking() public {
        // Create and complete launch using partial contributions
        vm.startPrank(creator);
        uint256 launchId = launcher.createLaunch(
            "TestToken",
            "TEST",
            "ipfs://test"
        );
        vm.stopPrank();

        // Get required amount
        (,,,,, uint256 ponderRequired) = launcher.getSaleInfo(launchId);

        // Mint directly
        ponder.mint(user1, ponderRequired);

        // Complete the launch
        vm.startPrank(user1);
        ponder.approve(address(launcher), ponderRequired);
        launcher.contribute(launchId, ponderRequired);
        vm.stopPrank();

        (address tokenAddress,,,,,bool launched, uint256 lpUnlockTime) = launcher.getLaunchInfo(launchId);
        assertTrue(launched, "Launch should be completed");

        // Try early withdrawal
        vm.startPrank(creator);
        vm.expectRevert(FiveFiveFiveLauncher.LPStillLocked.selector);
        launcher.withdrawLP(launchId);
        vm.stopPrank();

        // Move past lock period
        vm.warp(lpUnlockTime + 1);

        // Withdraw LP
        vm.startPrank(creator);
        launcher.withdrawLP(launchId);
        vm.stopPrank();

        // Verify LP receipt
        address pair = factory.getPair(tokenAddress, address(ponder));
        assertTrue(pair != address(0), "Pair should exist");
        assertGt(PonderERC20(pair).balanceOf(creator), 0, "Creator should have LP tokens");
    }

    receive() external payable {}
}
