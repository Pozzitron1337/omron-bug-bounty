// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../src/OmronDeposit.sol"; // Adjust the import path accordingly
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OmronDepositTest is Test {
    OmronDeposit public omronDeposit;
    MockERC20 public token;
    address public user = address(1);
    address public owner = address(this);
    address public claimManager = address(2);

    function setUp() public {
        // Deploy a mock ERC20 token
        token = new MockERC20("Mock Token", "MTK", 18);

        // Mint tokens to the user
        token.mint(user, 1000 ether);

        // Deploy the OmronDeposit contract
        address;
        whitelistedTokens[0] = address(token);
        omronDeposit = new OmronDeposit(owner, whitelistedTokens);

        // Set the claim manager
        omronDeposit.setClaimManager(claimManager);

        // Label addresses for clarity in test output
        vm.label(user, "User");
        vm.label(owner, "Owner");
        vm.label(claimManager, "ClaimManager");
    }

    function testBug1_DepositStopTimeUnderflow() public {
        // User approves OmronDeposit contract to spend tokens
        vm.startPrank(user);
        token.approve(address(omronDeposit), 100 ether);

        // User deposits 100 tokens
        omronDeposit.deposit(address(token), 100 ether);
        vm.stopPrank();

        // Fast forward time by 1 hour
        vm.warp(block.timestamp + 1 hours);

        // Owner stops deposits, setting depositStopTime to current block time
        omronDeposit.stopDeposits();
        uint256 depositStopTime = omronDeposit.depositStopTime();

        // Fast forward time by another 2 hours (simulate time after depositStopTime)
        vm.warp(block.timestamp + 2 hours);

        // User tries to calculate points (should not accrue after depositStopTime)
        uint256 pointsBefore = omronDeposit.calculatePoints(user);

        // Check if points calculation is correct
        // Expected points should only include the time up to depositStopTime
        uint256 expectedTimeElapsed = depositStopTime - (block.timestamp - 3 hours); // Last updated was initial deposit
        uint256 expectedPoints = (expectedTimeElapsed * 100 ether * 1e18) / (3600 * 1e18);

        // Log the results
        emit log_named_uint("Points Before Update", pointsBefore);
        emit log_named_uint("Expected Points", expectedPoints);

        // Assert that the points before update match expected points
        assertEq(pointsBefore, expectedPoints, "Points should only accrue up to depositStopTime");

        // Now, simulate the bug by updating the user's points after depositStopTime
        vm.prank(claimManager);
        omronDeposit.claim(user);

        // Get the user's info after claiming
        (,, uint256 pointBalanceAfter) = omronDeposit.getUserInfo(user);

        // Log the point balance after claim
        emit log_named_uint("Point Balance After Claim", pointBalanceAfter);

        // Due to the bug, pointBalanceAfter might be incorrect
        // In a correct implementation, pointBalanceAfter should be zero after claim
        // But due to underflow, it might have an incorrect large value

        // Check if pointBalanceAfter is zero (expected behavior)
        assertEq(pointBalanceAfter, 0, "Point balance after claim should be zero");
    }
}

/// @notice A simple mock ERC20 token for testing purposes
contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals_)
        ERC20(name, symbol)
    {
        _setupDecimals(decimals_);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function _setupDecimals(uint8 decimals_) internal virtual {
        // For compatibility with older versions of OpenZeppelin
    }
}