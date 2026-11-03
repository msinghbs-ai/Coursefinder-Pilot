-- CF-247 Layer 4 Inbox performance: read-only checks on production after migration 20261104410000 is released (Integration Controller).
-- Run with the Supabase SQL tool at Sydney minutes :x6 to :x8 only (never :35 to :42 or :47 to :48). Reads only; nothing is written.
-- Acceptance (Platform Admin 06:53 §6; AER decision 06:58 §5): the UNSW items in the screenshot, UNSW Bachelor of Actuarial Studies
-- (ca4df458-faa0-4b54-bc6c-9b81522e5595) and its Honours (09d58d03-7a71-452a-9096-125683d689dc), both course_entry_first_read and pending on
-- 4 Nov 2026 07:30 AEDT, provider 22657140-1cb0-4fa7-91df-90518ea8b35b; and three other universities (the largest groups).

-- 1 the definitions released are the ones built
select p.oid::regprocedure sig, md5(pg_get_functiondef(p.oid)) from pg_proc p
 where p.oid in ('security.layer4_inbox_items_v1()'::regprocedure, 'public.admin_layer4_inbox(text,jsonb)'::regprocedure);
-- expected: items_v1 2fa8b921d19f05dbd147f6833c71b784, admin_layer4_inbox 29705b99108e7a0b4d68fea398565d36

-- 2 counts without building items agree with the full list, for UNSW and the three largest universities; and how long each takes
with t0 as materialized (select clock_timestamp() t),
     c as materialized (select * from security.layer4_inbox_counts_v1(7)),
     t1 as materialized (select clock_timestamp() t from c limit 1),
     f as materialized (select kind, provider_id, count(*) n from security.layer4_inbox_items_v1() group by 1, 2),
     t2 as materialized (select clock_timestamp() t from f limit 1),
     u as (select provider_id from f where provider_id is not null group by 1 order by sum(n) desc limit 3
           union select '22657140-1cb0-4fa7-91df-90518ea8b35b'::uuid)
select (select count(*) from u) universities_checked,
       (select count(*) from (select kind, provider_id, n from c where provider_id in (select provider_id from u)
                              except select kind, provider_id, n from f where provider_id in (select provider_id from u)) x) counts_differ,
       (select jsonb_object_agg(kind, n) from c where provider_id = '22657140-1cb0-4fa7-91df-90518ea8b35b') unsw_by_kind,
       (select t from t1) - (select t from t0) counts_took, (select t from t2) - (select t from t1) full_list_took;
-- expected: counts_differ 0; counts_took well under a second

-- 3 the UNSW AER pill holds both screenshot items, and only UNSW's waiting AER items
with p as materialized (select * from security.layer4_inbox_items_v2('22657140-1cb0-4fa7-91df-90518ea8b35b', 'aer_review', null, false))
select count(*) waiting_aer, count(*) filter (where ref in ('ca4df458-faa0-4b54-bc6c-9b81522e5595', '09d58d03-7a71-452a-9096-125683d689dc')) screenshot_items,
       count(*) filter (where kind <> 'aer_review' or provider_id <> '22657140-1cb0-4fa7-91df-90518ea8b35b') foreign_items,
       clock_timestamp() - statement_timestamp() took from p;
-- expected: screenshot_items 2 while both wait, foreign_items 0

-- 4 hooks: what the Inbox finds (nothing until the recovery branch is released)
select security.layer4_inbox_hooks_v1() - 'kinds';
