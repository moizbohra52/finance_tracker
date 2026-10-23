# Shared split groups between app users — future idea

Date: 2026-10-23. Status: idea only, not designed or scheduled. Build after
`2026-10-23-split-expenses-design.md` ships and has been used for a while.

## Idea
Friends in a split group also use the app. Anyone in the group can add an
expense or a settlement, and everyone sees the same group, like Splitwise.
Today (v1) a group exists only on its owner's phone and friends are khata
contacts.

## Why not now
The app is single-user end to end: every table's RLS is
`user_id = auth.uid()`, sync pulls only the user's own rows, and each signed-in
account has its own local database. Sharing breaks all three and needs
invites, notifications and conflict handling. v1 delivers the user-side value
(correct expense, account and khata) without that.

## What would change
- **Identity**: a contact can be linked to an app user
  (`contacts.linked_user_id`), set when the friend accepts an invite. Finding
  users by phone number is a privacy decision of its own.
- **Membership**: group members carry a `user_id` when they are app users.
  Group-owned rows (groups, members, expenses, parts, settlements) get RLS by
  membership, e.g. a `security definer` function `private.is_split_member(group_id)`,
  instead of `user_id = auth.uid()`.
- **Personal books stay private**: each user's derived rows (their expense,
  account movement, khata entries) are still written only to their own
  `transactions` / `contact_transactions`, by their own device, from the shared
  group data. Nobody sees anyone's accounts or khata.
- **Sync**: pull group rows by membership, not by owner. When a friend's edit
  arrives, the device recomputes its own derived rows (the v1 `saveExpense`
  recompute, run on pull). Conflicts: last write wins per row, or expenses
  become editable only by their author; to decide.
- **Invites**: share link or code, accept screen, leave group, remove member.
- **Notifications**: FCM push when someone adds an expense or a settlement
  that involves the user (`08_NOTIFICATION_SYSTEM.md`).
- **Debt simplification** becomes possible once everyone sees the same group,
  because the khata of each user can follow the group instead of pairwise
  amounts; to decide.

## What v1 already does to make this easier
- Split tables are the source of truth, keyed by group, not computed from the
  khata.
- The user is a member row (`contact_id null`), so a member row can later point
  at an app user instead.
- Derived rows are recomputable from group data with deterministic ids, which
  is what a device needs when someone else edits the group.

## Open questions
- Can a v1 group be converted to shared, keeping its history?
- Who can edit or delete an expense: anyone, its author, or the group owner?
- What happens to a user's khata entries when they leave a group with an
  unsettled balance?
- Does a friend need an account to see the group (read-only web link)?
