// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

import "forge-std/Test.sol";
import "../src/OmronDeposit.sol";
import "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

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
        address[] memory whitelistedTokens = new address[](1);
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

    function testBug2_TokenDecimalsImpactOnPoints() public {
        // Deploy two mock tokens with different decimals
        MockERC20 token18 = new MockERC20("Token18", "T18", 18);
        MockERC20 token6 = new MockERC20("Token6", "T6", 6);

        // Create user addresses
        address userA = address(3);
        address userB = address(4);

        // Mint tokens to users
        token18.mint(userA, 1000 * (10 ** 18)); // 1000 tokens with 18 decimals
        token6.mint(userB, 1000 * (10 ** 6)); // 1000 tokens with 6 decimals

        // Add tokens to the whitelist
        vm.prank(owner);
        omronDeposit.addWhitelistedToken(address(token18));
        vm.prank(owner);
        omronDeposit.addWhitelistedToken(address(token6));

        // User A deposits 100 Token18 tokens
        vm.startPrank(userA);
        token18.approve(address(omronDeposit), 100 ether);
        omronDeposit.deposit(address(token18), 100 ether);
        vm.stopPrank();

        // User B deposits 100 Token6 tokens
        vm.startPrank(userB);
        token6.approve(address(omronDeposit), 100 * (10 ** 6));
        omronDeposit.deposit(address(token6), 100 * (10 ** 6));
        vm.stopPrank();

        // Advance time by 1 hour
        vm.warp(block.timestamp + 1 hours);

        // Calculate points for both users
        uint256 pointsUserA = omronDeposit.calculatePoints(userA);
        uint256 pointsUserB = omronDeposit.calculatePoints(userB);

        // Log the results
        emit log_named_uint("User A Points", pointsUserA);
        emit log_named_uint("User B Points", pointsUserB);

        // Due to the bug, pointsUserB will be significantly less than pointsUserA
        // Check that User B received fewer points due to decimal issue
        assertTrue(pointsUserB < pointsUserA, "User B received fewer points due to decimal handling issue");
    }

    function testReentrancyAttemptFails() public {
        // Deploy the malicious token
        ReentrantToken maliciousToken = new ReentrantToken("Malicious Token", "MAL", 18);

        // Set the target contract for reentrancy
        maliciousToken.setTarget(address(omronDeposit));

        // Whitelist the malicious token
        vm.prank(owner);
        omronDeposit.addWhitelistedToken(address(maliciousToken));

        // Mint tokens to the attacker
        maliciousToken.mint(address(this), 10 ether);

        // Approve the OmronDeposit contract to spend tokens
        maliciousToken.approve(address(omronDeposit), 10 ether);

        // Attempt to deposit tokens
        // The reentrancy attempt will fail due to the `nonReentrant` modifier
        vm.expectRevert();
        omronDeposit.deposit(address(maliciousToken), 1 ether);
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

contract MaliciousERC20 is ERC20 {
    constructor(string memory name, string memory symbol, uint8 decimals_)
        ERC20(name, symbol)
    {
        _setupDecimals(decimals_);
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // Override the transfer function to always return false
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        return false;
    }

    function _setupDecimals(uint8 decimals_) internal virtual {
        // For compatibility
    }
}

contract ReentrantToken is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_)
        ERC20(name, symbol)
    {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    // Reference to the OmronDeposit contract
    OmronDeposit public target;

    // Set the target contract
    function setTarget(address _target) public {
        target = OmronDeposit(_target);
    }

    // Override transferFrom to perform a reentrant call
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        // Reentrancy attempt: call deposit on the target contract
        if (address(target) != address(0)) {
            target.deposit(address(this), 1 ether);
        }
        // Proceed with normal transfer
        return super.transferFrom(sender, recipient, amount);
    }
}