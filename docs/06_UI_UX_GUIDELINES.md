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

**They seed the colour scheme; they are not used as `primary` directly.** On a
white surface the raw colours give 4.2:1 (ember), 1.6:1 (sun), 8.1:1 (cocoa)
and 2.0:1 (sand); text needs 4.5:1. So Material derives the roles from them,
using the `fidelity` variant so each keeps the logo colour's hue and strength
(ember stays a clear orange-red, about `#AA2F00` in light mode). Every accent,
in light and dark, is tested to keep 4.5:1 for primary text, button labels and
selected chips (`test/core/theme/accent_colors_test.dart`). The exact logo
colours remain available for swatches and branding, not for text.

**Default accent.** The default is still Indigo. Ember and sun sit close to the
expense (red) and payable (amber) colours used for money, so a brand-coloured
default would blur that meaning. Making a logo colour the default is a change
to `AppAccentColor.fromStorageKey` and the `indigo` entry only; saved choices
are unaffected because they are stored by key.

