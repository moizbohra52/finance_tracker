-- System categories shared by all users. Ids are fixed so the app's local
-- database can seed identical rows offline, and so this migration is safe to
-- re-run. `icon` is a stable key the app maps to an icon, not an asset path.
insert into public.categories (id, user_id, name, type, icon, is_system)
values
  ('c0000000-0000-4000-8000-000000000101', null, 'Salary', 'income', 'salary', true),
  ('c0000000-0000-4000-8000-000000000102', null, 'Business', 'income', 'business', true),
  ('c0000000-0000-4000-8000-000000000103', null, 'Freelance', 'income', 'freelance', true),
  ('c0000000-0000-4000-8000-000000000104', null, 'Interest', 'income', 'interest', true),
  ('c0000000-0000-4000-8000-000000000105', null, 'Gift Received', 'income', 'gift', true),
  ('c0000000-0000-4000-8000-000000000106', null, 'Refund', 'income', 'refund', true),
  ('c0000000-0000-4000-8000-000000000107', null, 'Other Income', 'income', 'other_income', true),
  ('c0000000-0000-4000-8000-000000000201', null, 'Food & Dining', 'expense', 'food', true),
  ('c0000000-0000-4000-8000-000000000202', null, 'Groceries', 'expense', 'groceries', true),
  ('c0000000-0000-4000-8000-000000000203', null, 'Transport', 'expense', 'transport', true),
  ('c0000000-0000-4000-8000-000000000204', null, 'Fuel', 'expense', 'fuel', true),
  ('c0000000-0000-4000-8000-000000000205', null, 'Shopping', 'expense', 'shopping', true),
  ('c0000000-0000-4000-8000-000000000206', null, 'Rent', 'expense', 'rent', true),
  ('c0000000-0000-4000-8000-000000000207', null, 'Bills & Utilities', 'expense', 'utilities', true),
  ('c0000000-0000-4000-8000-000000000208', null, 'Mobile & Internet', 'expense', 'mobile', true),
  ('c0000000-0000-4000-8000-000000000209', null, 'EMI & Loans', 'expense', 'emi', true),
  ('c0000000-0000-4000-8000-000000000210', null, 'Insurance', 'expense', 'insurance', true),
  ('c0000000-0000-4000-8000-000000000211', null, 'Health', 'expense', 'health', true),
  ('c0000000-0000-4000-8000-000000000212', null, 'Education', 'expense', 'education', true),
  ('c0000000-0000-4000-8000-000000000213', null, 'Entertainment', 'expense', 'entertainment', true),
  ('c0000000-0000-4000-8000-000000000214', null, 'Travel', 'expense', 'travel', true),
  ('c0000000-0000-4000-8000-000000000215', null, 'Subscriptions', 'expense', 'subscriptions', true),
  ('c0000000-0000-4000-8000-000000000216', null, 'Personal Care', 'expense', 'personal_care', true),
  ('c0000000-0000-4000-8000-000000000217', null, 'Gifts & Donations', 'expense', 'donation', true),
  ('c0000000-0000-4000-8000-000000000218', null, 'Other Expense', 'expense', 'other_expense', true)
on conflict (id) do nothing;
