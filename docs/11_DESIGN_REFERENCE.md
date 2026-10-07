# Design Reference — Uploaded Finance App UI

## Reference Source
The user-provided image is a visual design reference only.

Use it to understand:
- visual hierarchy
- spacing
- card composition
- typography scale
- onboarding presentation
- dashboard information density
- analytics layout
- bottom navigation
- use of a strong accent color
- modern fintech visual language

## Important Rule
Do NOT create a pixel-for-pixel copy of the reference image or copy another product's branding.

The reference is inspiration. Our application must have its own:
- brand identity
- icons
- illustrations
- colors
- typography
- layouts
- component styling

## Elements We Can Take as Inspiration

### 1. Onboarding
Reference characteristics:
- large bold headline
- short supporting description
- strong accent background
- prominent CTA
- simple login link at bottom
- minimal visual clutter

Our app can use this structure.

Suggested onboarding messages:
1. "Know Where Your Money Goes"
2. "Track Every Rupee"
3. "Stay Ahead of Your Payments"

### 2. Dashboard
Use the reference's information hierarchy:
- greeting
- notification action
- prominent wallet/current balance
- account/card summary
- quick actions
- recent activity
- bottom navigation

For our application, the dashboard should additionally show:
- Opening Balance
- Current Balance
- Today's Income
- Today's Expense
- Receivable
- Payable

### 3. Balance Card
Make the current balance the most prominent financial number.

Example:

Current Balance
₹17,298.92

Opening Balance
₹10,000

This month
+₹12,500 income
-₹5,201 expense

Provide an eye/visibility action if useful.

### 4. Quick Actions
Use compact rounded action buttons inspired by the reference.

Actions:
- Income
- Expense
- Credit
- Debit
- Transfer
- Reminder

Do not overload the first screen.

### 5. Recent Transactions
Use a clean timeline/list:
- category/contact icon
- title
- date/time
- transaction type
- amount

Example:

Food
Today, 1:32 PM
Expense
-₹250

Salary
Today, 10:00 AM
Income
+₹45,000

### 6. Analytics
Reference analytics characteristics:
- clear headline metric
- date/month selector
- compact chart
- category breakdown
- readable labels

Our analytics screen should provide:
- total spending
- total income
- net cash flow
- monthly trend
- category breakdown
- account breakdown
- receivable/payable summary

### 7. Bottom Navigation
Use a simple five-item navigation:

Home
Transactions
Khata
Reports
Profile

The center action may be a floating/add button rather than a normal navigation destination.

### 8. Theme
The reference demonstrates that a strong accent color can give the app a distinctive identity.

For this app:
- create a centralized color system
- support Light/Dark/System modes
- allow configurable accent color
- never hardcode colors inside feature widgets

The final palette should be selected for readability and accessibility rather than copied exactly from the reference.

## UX Direction
Aim for:
- premium
- minimal
- friendly
- fast
- financial clarity
- low cognitive load

Avoid:
- excessive gradients
- too many cards
- excessive charts
- tiny text
- overly decorative UI
- confusing accounting terminology

## Screen-specific Inspiration

### Splash
Minimal branded mark and short loading state.

### Onboarding
Strong visual identity + short copy + one primary CTA.

### Login/Register
Clean form with generous spacing and clear primary action.

### Home
Balance first, then quick actions, then recent activity.

### Add Expense/Income
Amount first, category second, account/payment method third, optional details after.

### Khata
Person name + receivable/payable amount should be immediately visible.

### Reports
One primary metric + chart + breakdown. Avoid dashboard overload.

### Settings
Grouped sections with clear labels and icons.

## Component Direction
Create reusable components:
- BalanceCard
- SummaryCard
- QuickActionButton
- TransactionTile
- AccountCard
- ContactBalanceTile
- SpendingChartCard
- CategoryBreakdown
- SectionHeader
- AppBottomNavigation
- AppFloatingAction
- EmptyState
- ErrorState
- LoadingSkeleton

## Responsive Rule
The uploaded reference is shown in iPhone-style mockups. Do not hardcode dimensions based on that image.

Build responsive Flutter layouts that work on:
- small Android phones
- large Android phones
- iPhones
- tablets where practical

## Implementation Rule
Before implementing a screen, Claude should compare the intended screen with this design reference and ask:

1. What visual hierarchy is useful?
2. What can be simplified?
3. Which elements are actually required by our product?
4. Can the component be reused?
5. Does the layout remain usable with real data?

The goal is to create a better product inspired by the reference, not to reproduce the reference.
