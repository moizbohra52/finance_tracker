# Testing Strategy

## Unit tests
Required for:
- balance calculations
- budget calculations
- khata calculations
- date period calculations
- recurring schedule calculation
- transaction validation
- sync conflict/idempotency logic

## Widget tests
Test:
- login form validation
- transaction form
- balance card
- filters
- empty/error states
- theme switching

## Integration tests
Test:
- register/login/logout
- password reset
- create account
- opening balance
- add income
- add expense
- transfer
- khata credit/debit
- reminder
- offline transaction then sync

## Security tests
Verify:
- unauthenticated access denied
- cross-user access denied
- update/delete ownership enforced

## Regression
Every phase must retain previous phase tests.

## Test data
Use deterministic test fixtures.
Never use real personal financial data.

## Release gates
- flutter analyze clean
- unit tests pass
- widget tests pass
- critical integration tests pass
- no known critical security issue
- release build succeeds
