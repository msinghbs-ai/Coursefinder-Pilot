-- S670 scenarios on the scratch database after migration 20261118220000 (applied twice). Every line prints PASS or FAIL; run.sh fails the run on FAIL or ERROR.
create or replace function t.chk(p_name text, p_ok boolean) returns void language plpgsql as $f$ begin raise notice '%', case when coalesce(p_ok, false) then 'PASS ' else 'FAIL ' end || p_name; end $f$;
create or replace function t.sp(p_name text) returns int language sql stable as $f$ select jsonb_array_length(security.course_entry_shared_page_v1((select id from t.named where name = p_name))) $f$;
create or replace function t.b70(p_name text) returns int language sql stable as $f$ select n from t.shared_s670_before where name = p_name $f$;

select t.chk('HB1 before: the 8 Nov rule held a hand-bound, hand-locked course for a refused binding (H1 shared with 1)', t.b70('H1') = 1);
select t.chk('HB1 after: a hand-bound, hand-locked course ignores a refused binding on its page (H1 shared with 0)', t.sp('H1') = 0);
select t.chk('HB2 another BOUND course on the page still counts for a hand-bound course (H2 stays 1)', t.b70('H2') = 1 and t.sp('H2') = 1);
select t.chk('HB3 an AMBIGUOUS course on the page still counts for a hand-bound course (H3 stays 1)', t.sp('H3') = 1);
select t.chk('HB4 two refused bindings are both ignored (H4 before 2, after 0)', t.b70('H4') = 2 and t.sp('H4') = 0);
select t.chk('HB5 a pace twin stays held: both twins are bound (H5 stays 1, J5 stays 1)', t.sp('H5') = 1 and t.sp('J5') = 1);
select t.chk('HB6 a basis outside the list keeps the old rule even with a hand lock (H6 stays 1)', t.sp('H6') = 1);
select t.chk('HB7 a strongly identified course with a hand lock is released too (A4 before 1, after 0)', t.b70('A4') = 1 and t.sp('A4') = 0);
select t.chk('HB8 a hand binding without a lock is released by the wider basis list (A6 before 1, after 0)', t.b70('A6') = 1 and t.sp('A6') = 0);
select t.chk('HB9 the 8 Nov cases are unchanged (A1 0, A2 1, A3 1, A5 1, A7 1, A8 0, A9 0)',
             t.sp('A1') = 0 and t.sp('A2') = 1 and t.sp('A3') = 1 and t.sp('A5') = 1 and t.sp('A7') = 1 and t.sp('A8') = 0 and t.sp('A9') = 0);
select t.chk('HB10 the refused course is not released: J1 (own mismatch) still sees H1', t.sp('J1') = 1);
update pipeline.platform_toolset_settings set value = '1'::jsonb where key = 'entry.shared_page_hand_lock_holds';
select t.chk('HB11 the switch at 1 restores the hand-lock rule of 8 Nov (H1 1, H4 2, A4 1; unlocked A6 stays 0)', t.sp('H1') = 1 and t.sp('H4') = 2 and t.sp('A4') = 1 and t.sp('A6') = 0);
update pipeline.platform_toolset_settings set value = '["cricos_code", "nzqa_code", "adapter_code", "exact_title", "title_level"]'::jsonb where key = 'entry.shared_page_own_bases';
select t.chk('HB12 the switch at 1 and the 8 Nov basis list restore 8 Nov exactly (every course as before)',
             not exists (select 1 from t.shared_s670_before b where b.n is distinct from t.sp(b.name)));
update pipeline.platform_toolset_settings set value = '0'::jsonb where key = 'entry.shared_page_hand_lock_holds';
select t.chk('HB13 the switch at 0 with the 8 Nov list releases locked strong bases only (A4 0, H1 stays 1)', t.sp('A4') = 0 and t.sp('H1') = 1);
select t.chk('HB14 the migration wrote one audit event and decided nothing',
             (select count(*) from pipeline.admin_control_events e where e.detail->>'migration' = '20261118220000') = 1
             and not exists (select 1 from pipeline.layer4_review_items i where i.status <> 'pending' and i.decided_at is not null));
do $$ begin raise notice 'hand-bound: scenarios finished'; end $$;
