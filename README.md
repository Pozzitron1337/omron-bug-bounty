## Omron Bug Bounty

https://immunefi.com/bug-bounty/omron/information/#top

Found only critical bug №2.

# Bug №1 - NOT confirmed - Underflow calculation in calculating points

The suspicion about Bug 1 was that an underflow might occur in the `_calculatePointsDiff` function when calculating timeElapsed if depositStopTime is less than _user.lastUpdated. It was believed that this could lead to incorrect point accrual for users after deposits were stopped.

To verify this suspicion, you wrote tests using Foundry, where:

1. Had a user make a deposit into the contract.
2. Advanced time by a certain period to accumulate points.
3. Stopped deposits by calling stopDeposits(), which sets depositStopTime.
4. Advanced time further so that block.timestamp became greater than depositStopTime.
5. Calculated the user's points and checked whether they were accrued correctly.
5. The test aimed to detect an underflow in the calculation of timeElapsed, which could have resulted in incorrect point values (such as very large numbers due to underflow).

However, upon running the tests, i found that:

1) Points were accrued correctly, with no signs of underflow.
2) Tests passed successfully, confirming that the contract correctly handles the scenario where depositStopTime is less than _user.lastUpdated.

Thus, Bug 1 was not confirmed. The contract includes the necessary checks to prevent underflow and correctly calculates accumulated points after deposits are stopped.

# Bug №2 - сonfirmed - Ignoring Token Decimals in Point Calculations

The OmronDeposit smart contract fails to account for varying token decimal places when calculating user points. This oversight leads to unfair point accrual, disadvantaging users who deposit tokens with fewer decimals. The test with proof is provided in `test/OmronDeposit.t.sol` by test №2.

Description
Issue
Function Affected: deposit
Problem: The contract adds the raw `_amount` to `user.pointsPerHour` without adjusting for the token's decimals.

```
user.pointsPerHour += _amount;
```

Consequence: Tokens with fewer decimals contribute less to `pointsPerHour` than tokens with more decimals, even if the nominal deposit amounts are the same.
Example:

User A: Deposits 100 units of a token with 18 decimals.
User B: Deposits 100 units of a token with 6 decimals.

Result: User A accrues significantly more points than User B, despite depositing the same nominal amount.

Impact
Unfair Advantage: Users depositing tokens with more decimals earn disproportionately more points.
User Dissatisfaction: This can lead to user frustration and loss of trust in the platform's fairness.
Financial Inequity: Potential financial losses for users depositing tokens with fewer decimals.
Recommendation

Solution
Normalize Deposit Amounts: Adjust the deposited _amount based on the token's decimals to ensure consistency in point calculations.

```
// Retrieve the token's decimals
uint8 decimals = ERC20(_tokenAddress).decimals();

// Normalize the amount to 18 decimals
uint256 normalizedAmount = _amount * (10 ** (18 - decimals));

user.pointsPerHour += normalizedAmount;
```
Benefits:
1) Fairness, which ensures all users earn points proportional to the nominal value of their deposits.
Consistency: Maintains equitable treatment of all tokens regardless of their decimal configuration.
2) Trust, that enhances user confidence in the platform's integrity.

Thus, by normalizing deposit amounts according to token decimals, the contract can fairly calculate user points, rectifying the inequity caused by the current implementation.

# Bug №3 - NOT confurmed - Reentrancy

The concern was that despite using the nonReentrant modifier, the contract could still be vulnerable to reentrancy attacks if a malicious token with a custom implementation of transferFrom or transfer was used. The suspicion was that such a token could exploit the contract during an external call, especially if the contract did not strictly follow the Checks-Effects-Interactions pattern. The proof was implemented in test `testReentrancyAttemptFails`