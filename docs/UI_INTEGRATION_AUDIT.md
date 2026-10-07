# UI Integration Audit — Finance Tracker / Digital Khata

**Date:** 2026-10-07
**Status:** Pre–PHASE 07 readiness check
**Scope:** All screens implemented in PHASE 00–06, GetX routing, controller/repository wiring, navigation, state handling.
**Method:** Inspected `lib/` source, `routes/app_pages.dart`, `routes/app_routes.dart`, `bindings/initial_binding.dart`, `main.dart`, and all feature view/controller/repository/datasource files. No code was modified.

---

## 1. Entry point and startup flow

`lib/main.dart`:

- `initialRoute` = `/splash` (`AppPages.initial`).
- `GetMaterialApp` uses `AppPages.routes`.
- `InitialBinding` registers permanently: `StorageService`, `ThemeController`, `ConnectivityService`, `AuthRepository`, `ProfileRepository`, `AuthController`, `AccountRepository`, `CategoryRepository`, `TransactionRepository`.

**Startup sequence (verified):**

1. **Splash** (`/splash`) → `SplashController.takeStartRoute()` returns `/dashboard` if signed in, `/onboarding` otherwise.
2. **Onboarding** (`/onboarding`, guest-guarded) → buttons to `/login` and `/register`. No controller (local UI state).
3. **Login** (`/login`) → sign in → auth controller pushes `/dashboard` on `signedIn`; link to `/forgot-password`; "Create one" → `/register`.
4. **Register** (`/register`) → sign in → `/dashboard`.
5. **Forgot password** (`/forgot-password`) → email → recovery session → `/reset-password`.
6. **Reset password** (`/reset-password`, auth-guarded) → new password → `/dashboard`.

Authenticated users land on the dashboard shell; unauthenticated users see onboarding.

---

## 2. Screen / feature audit table

| Screen | Exists | Route | Controller | Repository | UI Complete | Navigation Complete | Status |
|---|---|---|---|---|---|---|---|
| Splash | ✅ | `/splash` ✅ | `SplashController` ✅ | N/A | ✅ | ✅ → onboarding / login | **Complete** |
| Onboarding | ✅ | `/onboarding` ✅ | (none — intentional) | N/A | ✅ 3-page intro | ✅ → login / register | **Complete** |
| Login | ✅ | `/login` ✅ | `LoginController` ✅ | `AuthRepository` ✅ | ✅ | ✅ → register / dashboard | **Complete** |
| Register | ✅ | `/register` ✅ | `RegisterController` ✅ | `AuthRepository` ✅ | ✅ | ✅ → login / dashboard | **Complete** |
| Forgot Password | ✅ | `/forgot-password` ✅ | `ForgotPasswordController` ✅ | `AuthRepository` ✅ | ✅ | ✅ → reset-password | **Complete** |
| Reset Password | ✅ | `/reset-password` ✅ | `ResetPasswordController` ✅ | `AuthRepository` ✅ | ✅ | ✅ → dashboard | **Complete** |
| Home / Dashboard | ✅ | `/dashboard` ✅ | `ProfileController` ✅ | `ProfileRepository` ✅ | ⚠️ shell done, content is empty placeholder | ✅ tab switching works | **Partial** |
| Bottom Navigation | ✅ | N/A | N/A | N/A | ✅ (nav rail + bottom nav) | ✅ | **Complete** |
| Accounts | ✅ | `/accounts` ✅ | `AccountController` ✅ | `AccountRepository` ✅ | ✅ list + edit + detail + empty | ✅ → form / detail | **Complete** |
| Opening Balance | ✅ | `/account-form` ✅ | `AccountController` ✅ | `AccountRepository` ✅ | ✅ amount + date fields | ✅ from account list | **Complete** |
| Income | ⚠️ form exists | ❌ no route | `TransactionController` (unbound) | `TransactionRepository` ✅ | ✅ fields: type/amount/date/account/category | ❌ no route, no nav entry | **Missing route** |
| Expense | ⚠️ form exists | ❌ no route | `TransactionController` (unbound) | `TransactionRepository` ✅ | ✅ fields: type/amount/date/account/category | ❌ no route, no nav entry | **Missing route** |
| Transaction List | ✅ view exists | ❌ no route | `TransactionController` (unbound) | `TransactionRepository` ✅ | ✅ list + filter + search | ❌ tab is placeholder | **Missing route** |
| Transaction Detail | ✅ view exists | ❌ no route | `TransactionController` (unbound) | `TransactionRepository` ✅ | ✅ | ❌ no route | **Missing route** |
| Khata / Contacts List | ✅ view exists | ❌ no route | `ContactController` (unbound) | `ContactRepository` ✅ | ✅ list + search + filter + reminders | ❌ tab is placeholder | **Missing route** |
| Add Credit / Add Debit | ⚠️ in contact form | ❌ no route | `ContactController` (unbound) | `ContactRepository` ✅ | ✅ type dropdown (credit/debit/payment) | ❌ no route | **Missing route** |
| Contact Details | ✅ view exists | ❌ no route | `ContactController` (unbound) | `ContactRepository` ✅ | ✅ detail + transaction history | ❌ no route | **Missing route** |

**Legend:** ✅ present and wired; ⚠️ present but incomplete; ❌ absent.

---

## 3. What is missing

### 3.1 Missing route constants (`lib/routes/app_routes.dart`)

The following constants are not defined anywhere in the codebase:

- `transactionList`, `transactionForm`, `transactionDetail`
- `contactList` (khata list), `contactForm`, `contactDetail`

### 3.2 Missing route definitions (`lib/routes/app_pages.dart`)

No `GetPage` entries exist for any transaction or contact screen. The `TransactionController` and `ContactController` are never constructed on any route and are not bound in `InitialBinding`.

### 3.3 Navigation targets missing from the app shell

`lib/features/dashboard/views/app_shell_view.dart` reserves 5 tabs:

| Index | Destination | Currently renders |
|---|---|---|
| 0 | Home | `DashboardView` ✅ (but empty) |
| 1 | Transactions | `FeaturePlaceholderView` ❌ |
| 2 | Khata | `FeaturePlaceholderView` ❌ |
| 3 | Reports | `FeaturePlaceholderView` ❌ |
| 4 | Profile | `ProfileView` ✅ |

Tabs 1–3 are unimplemented placeholders. Tab 0 shows an empty "Welcome" state — no balances, no recent activity, no accounts.

### 3.4 Controllers that exist but are never bound

| Controller | Views reference it | Bound anywhere? |
|---|---|---|
| `TransactionController` | `transaction_list_view.dart`, `transaction_form_view.dart`, `transaction_detail_view.dart` | ❌ No |
| `ContactController` | `contact_list_view.dart`, `contact_form_view.dart`, `contact_detail_view.dart` | ❌ No |

### 3.5 Backend-only features (code exists but 0% reachable from UI)

1. **Contacts / Khata module** — fully implemented end-to-end:
   - `domain/entities/contact.dart` with balance math (`getCurrentBalance`, `getReceivable`, `getPayable`)
   - `data/models/contact.dart`, `data/models/contact_transaction.dart`
   - `data/datasources/contact_datasource.dart` (Supabase)
   - `data/repositories/contact_repository.dart`
   - `features/contacts/controller/contact_controller.dart` (search, filter, reminders)
   - `features/contacts/views/contact_list_view.dart`, `contact_form_view.dart`, `contact_detail_view.dart`
   - `widgets/contact_list_item.dart`

   **None of it is routable.** `ContactRepository` is not in `InitialBinding`, so even wiring routes would break without adding it.

2. **Transactions module** — views + controller + repository exist, and `TransactionRepository` is initialized in `InitialBinding`, but there are no routes and no nav entry. This is a routing gap rather than a full backend-only gap.

### 3.6 Dashboard content gap

`DashboardView` is an `EmptyState` placeholder. There is no:

- Opening balance / total balance summary
- Recent transactions
- Accounts overview / quick-add
- Khata summary (receivables vs payables)

This means even the "complete" tabs (Accounts, Profile) sit on an otherwise empty home.

### 3.7 Minor wiring issue

`/account-detail` in `app_pages.dart` constructs `AccountDetailView()` with no argument-passing mechanism, even though the view reads the `Account` from `Get.arguments`. Edit-from-list does not actually work as defined.

---

## 4. End-to-end flow as it stands today

```
Splash
 └─ [not authenticated] Onboarding ─ Login / Register ─ Forgot Password ─ Reset Password
 └─ [authenticated]           Dashboard (shell)
                              ├─ Settings ✅
                              ├─ Profile ✅
                              ├─ Accounts ✅ (add / edit / opening balance / detail)
                              ├─ Transactions ⚠️  placeholder
                              ├─ Khata        ⚠️  placeholder
                              └─ Reports      ❌  placeholder
```

A user can: create an account, sign in, add/edit accounts with opening balances, view account lists and details, change password, reset password, and open settings/profile. A user **cannot** create or view any income/expense transaction, cannot use the khata/contacts ledger at all, and the home dashboard shows nothing financial.

---

## 5. What must be completed before PHASE 07

**Priority A — make the app navigable (blocker for any later phase):**

1. Add route constants and `GetPage` definitions in `app_routes.dart` + `app_pages.dart`:
   - Transactions: list, form (add/edit), detail.
   - Contacts: list, form (add/edit), detail.
2. Wire both tabs into `AppShellView` (replace the `FeaturePlaceholderView`s).
3. Register `ContactRepository` in `InitialBinding` (it is not bound today).
4. Fix the `/account-detail` route to pass the `Account` via `Get.arguments`.

**Priority B — make the app usable (required for a real end-to-end flow):**

5. Implement dashboard tab content: opening/total balance summary, recent transactions, accounts list, quick "add transaction" entry.
6. Add navigation links: dashboard → accounts, accounts → income/expense, account → opening balance, contact detail → add credit / add debit / contact transaction history.
7. Add loading / empty / error states to the transaction and contact views (present in some, inconsistent across the three).
8. Implement the Reports tab (currently a bare placeholder).

**Priority C — polish (deferable past PHASE 07):**

9. Consolidate state handling in transaction/contact views (uniform loading/empty/error rendering).
10. Add offline indicators and sync UI for transaction/khata writes.

---

## 6. Verification notes

- Verified `app_pages.dart` route list directly (13 entries; none transaction/contact).
- Grepped the whole `lib/` tree for `transactionList|transactionForm|transactionDetail|contactList|contactForm|contactDetail` — no matches.
- Grepped for `ContactController|ContactRepository|ContactDatasource` — referenced only inside `lib/features/contacts/` and `lib/data/`, never in `bindings/` or `routes/`.
- Verified auth navigation through `AuthController._onStatus()` (`signedIn` → dashboard, `passwordRecovery` → reset-password) and `SplashController` start-route logic.
- Verified onboarding bottom buttons call `Get.toNamed` to `AppRoutes.login` / `AppRoutes.register`.
- Analyzer was run on edited files during the earlier contacts implementation; no changes were made in this session.
