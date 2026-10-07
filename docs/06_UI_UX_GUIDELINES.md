# UI/UX Guidelines

## Visual direction
Modern premium finance application:
- clean
- minimal
- readable
- professional
- touch-friendly
- consistent

Do not copy another app's exact UI.

## Color semantics
Use centralized theme tokens.
Semantic colors:
- income/success
- expense/error
- receivable/info
- payable/warning
Do not hardcode colors inside feature widgets.

## Dashboard
Prioritize:
1. current balance
2. income/expense summary
3. receivable/payable
4. recent transactions
5. budget/reminders

## Add transaction
Minimize steps.
Amount should be prominent.
Use sensible defaults.
Keyboard should open quickly for amount input.

## Forms
- labels
- validation
- helper/error text
- disabled/loading submit state
- keyboard type appropriate to field

## Lists
Use:
- date grouping
- transaction icon
- amount
- category/contact
- compact metadata
- swipe only where discoverable and safe

## Empty states
Explain what the user can do next.

## Accessibility
- readable font sizes
- sufficient contrast
- touch targets >= 44x44 where practical
- do not communicate meaning by color alone

## Responsive
Support common Android/iOS phone sizes and tablets where practical.

## Loading
Prefer skeletons for dashboard/list data and compact progress indicators for actions.

## Design Reference
For visual direction, also read `docs/11_DESIGN_REFERENCE.md`. The user-provided reference image is inspiration only; do not reproduce it pixel-for-pixel.
