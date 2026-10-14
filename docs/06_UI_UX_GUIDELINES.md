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

## Brand colours (the logo)
The logo (`assets/logo.png`) has four colours, sampled from its flat areas and
defined once in `AppColors` (`core/theme/app_tokens.dart`):

| Name | Hex | Where in the logo |
|---|---|---|
| Ember | `#E24201` | top-left piece (orange-red) |
| Sun | `#F7C401` | top-right piece (yellow) |
| Cocoa | `#7B4013` | bottom-left piece (brown) |
| Sand | `#DEAC72` | bottom-right piece (tan) |

They are offered in Settings > Appearance as the **Logo colours** accents
(`AppAccentColor`), above the other accents. Choosing one recolours the whole
app, including charts, which take their colours from the theme.

**They are swatches; they are not used as `primary` directly.** On a white
surface the raw colours give 4.2:1 (ember), 1.6:1 (sun), 8.1:1 (cocoa) and
2.0:1 (sand); text needs 4.5:1. Letting Material darken them at their own hue
looked muddy (sun became olive, sand khaki), so every accent instead has four
hand-picked shades, `AccentTones` in `core/theme/app_accent_color.dart`:

| Shade | Used as |
|---|---|
| `deep` | `primary` in light mode, filled buttons, the balance card (both modes) |
| `light` | `primary` in dark mode |
| `tint` | selected chips and containers in light mode |
| `ink` | text on `tint`, and on `light` in dark mode |

The shades are deliberately muted (moderate saturation, soft pastels in
dark mode) so the app looks calm; each keeps its seed's hue. For example
Sun's `deep` is antique gold `#8F6B25` (not olive, and not a loud amber),
Ember's is terracotta `#B5501F` and Indigo's is slate indigo `#4B57A8`.
Settings shows each accent's `deep` shade on its swatch, so the swatch
matches the result. Every accent, in light and dark, is tested to keep 4.5:1 for
primary text, button labels and selected chips, and each logo accent to keep
its logo colour's hue (`test/core/theme/accent_colors_test.dart`). Material
still derives the quieter roles (secondary, tertiary, error) from `deep`.

**Default accent.** The default is still Indigo. Ember and sun sit close to the
expense (red) and payable (amber) colours used for money, so a brand-coloured
default would blur that meaning. Making a logo colour the default is a change
to `AppAccentColor.fromStorageKey` and the `indigo` entry only; saved choices
are unaffected because they are stored by key.

**Neutral surfaces.** Pages, cards, text and lines are fixed neutral greys
(`AppColors.page*`, `card*`, `text*`, `fill*`, `line*`), the same for every
accent. Accent-tinted or navy surfaces clashed with warm accents.

## Visual style
Inspired by fintech UI kits such as Coinpay (inspiration only, see
`docs/11_DESIGN_REFERENCE.md`):
- **Page and cards.** Light mode puts white, borderless cards with a soft
  shadow on a light grey page (`#F4F5F7`). Dark mode uses a charcoal page
  (`#0E1014`) with cards that keep a faint outline, since shadows do not show
  on a dark page.
- **Shapes.** Buttons, the floating action button, chips and the navigation
  indicator are pills; cards and inputs keep rounded corners
  (`AppRadius.lg` / `AppRadius.md`); sheets and dialogs use `AppRadius.xl`.
- **Inputs** are filled with the card colour, so fields read as white on the
  grey page.
- **Icons** in rows, tiles and empty states sit in a tinted circle
  (`IconBadge`), never a bare icon or a rounded square.
- **Balance card.** It uses the accent's `deep` shade in both modes (light
  `primary`, dark `primaryContainer`) with white text, and its income and
  expense arrows are white too: the arrows and labels carry the meaning, and
  green or red on a coloured card clashed with accents such as Sun or Rose.

## Shared components
Feature screens compose these instead of building rows, badges or banners
inline (`lib/core/widgets`, `lib/widgets`):

| Need | Component |
|---|---|
| Tinted icon or initial in a circle | `IconBadge`, `IconBadge.initial` |
| Status label (Over budget, Overdue) | `StatusPill` |
| Any list row: badge, title, detail, trailing value | `AppListTile` (`flatPadding` when the row sits directly on the page) |
| Card of rows with aligned dividers | `AppListCard` |
| Card, optionally tappable | `AppCard(onTap:)` |
| Transaction / contact / account row | `TransactionListItem`, `ContactBalanceTile`, `AccountTile` |
| Category chips (no check mark; selected = thicker primary border) | `CategoryPicker` |
| Settings row with a value and chevron | `SettingsTile` (inside `AppListCard`) |
| Small figure tile, planning shortcut, home action | `SummaryTile`, `PlanTile`, `QuickActionButton` |
| Error, success, info or notice box | `InlineMessage` (`tone`, optional `title`, `action`) |
| Nothing here / failed to load | `EmptyState`, `ErrorState` |
| Buttons with loading state | `AppButton` |

Colours and sizes come from the theme and `AppSizes`, `AppSpacing` and
`AppRadius`, never literals in feature widgets.

