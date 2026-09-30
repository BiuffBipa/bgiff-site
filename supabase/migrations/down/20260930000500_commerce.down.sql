alter table if exists entries drop constraint if exists entries_paid_order_fk;
drop table if exists entitlements, refunds cascade;
drop function if exists invoices_immutable() cascade;
drop table if exists invoices cascade;
drop function if exists next_number(text, text);
drop table if exists number_counters, order_lines, orders, coupons, prices, products cascade;
