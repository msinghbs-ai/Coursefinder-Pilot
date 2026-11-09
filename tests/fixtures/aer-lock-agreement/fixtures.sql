-- CF-247 AER lock agreement: the cases. Part before: the mismatch with the live rule (35281a19) and live D-R2 (2e93bd9b); part after: the rule and D-R2 agree on what a lock blocks.
select :'part' = 'before' as is_before \gset
create or replace function fxl.cls(p_k text) returns jsonb language sql stable as $$ select security.aer_recovery_rule_v1(item) from fxl.cases where k = p_k $$;
create or replace function fxl.dr2(p_k text) returns jsonb language sql stable as $$
  select security.course_entry_correction_check_v1(c.item, c.course, (select pg.url from pipeline.coverage_course_pages pg where pg.course_id = c.course)) from fxl.cases c where c.k = p_k $$;
create or replace function fxl.lockrefused(p_k text) returns boolean language sql stable as $$ select coalesce(fxl.dr2(p_k)->>'why', '') like '%manual lock%' $$;

\if :is_before
-- B1 the defect, reproduced: the rule makes eligible what D-R2 refuses for a lock on the page fields
do $$ begin
  perform fxl.ok((fxl.cls('pair_a')->>'eligible')::boolean and fxl.lockrefused('pair_a'), 'before (defect reproduced): a course with a course_url + official_url lock is eligible by the rule and refused by D-R2 (the course has a manual lock)');
  perform fxl.ok((fxl.cls('single_official')->>'eligible')::boolean and fxl.lockrefused('single_official'), 'before (defect reproduced): a lock on official_url alone is eligible by the rule and refused by D-R2');
  perform fxl.ok((fxl.cls('pair_changed')->>'eligible')::boolean and fxl.lockrefused('pair_changed'), 'before (defect reproduced): a changed_conditions item with the lock pair is eligible by the rule and refused by D-R2');
  -- what already agreed
  perform fxl.ok(fxl.cls('entry_req')->>'class' = 'human_assisted' and fxl.lockrefused('entry_req'), 'before: a lock on entry_requirements is human_assisted by the rule and refused by D-R2 (they agreed)');
  perform fxl.ok((fxl.cls('unlocked')->>'eligible')::boolean and not fxl.lockrefused('unlocked') and (fxl.dr2('unlocked')->>'ok')::boolean, 'before: an unlocked eligible item is eligible and passes D-R2');
  perform fxl.ok((fxl.cls('other_field')->>'eligible')::boolean and not fxl.lockrefused('other_field'), 'before: a lock on a field D-R2 does not list (tuition) blocks neither');
  perform fxl.ok((select count(*) from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code = 'course_entry_first_read' and (security.aer_recovery_rule_v1(i.id)->>'eligible')::boolean
                    and exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = i.entity_id and l.field in ('course_url', 'official_url'))) = 4,
                 'before: 4 locked items are eligible by the rule (pair_a, pair_b, single_official, pair_changed)');
end $$;
-- B2 the held step spends its scan on them: its outcome for a locked eligible item is the D-R2 refusal
do $$ declare v_o text; begin
  begin  -- a scan wide enough to reach every waiting item, in a sub-transaction that is rolled back (the fixture has no aer.schedule_held_scan row; live scans 40)
    insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values ('pipeline', 'aer.schedule_held_scan', 'scan', 'number', '1000'::jsonb)
      on conflict (toolset_key, key) do update set value = excluded.value;
    select outcome into v_o from security.aer_schedule_held_v1(1000) h where h.item_id = (select item from fxl.cases where k = 'pair_a');
    raise exception 'fx_rollback';
  exception when others then if sqlerrm <> 'fx_rollback' then raise; end if; end;
  perform fxl.ok(v_o like 'held, not correctable: the course has a manual lock%', 'before (defect reproduced): the held step reaches the locked item and records "' || coalesce(v_o, '?') || '"');
end $$;
\else
-- A1 the rule never makes eligible what D-R2 refuses for a lock (negative)
do $$
declare r record;
begin
  for r in select k from fxl.cases where k in ('pair_a', 'pair_b', 'single_official', 'pair_changed') loop
    perform fxl.ok(not (fxl.cls(r.k)->>'eligible')::boolean and fxl.cls(r.k)->>'class' = 'human_assisted' and fxl.lockrefused(r.k),
                   'after: ' || r.k || ' (a page lock) is human_assisted, not eligible, and D-R2 refuses it for the lock too: ' || (fxl.cls(r.k)->>'why'));
  end loop;
  perform fxl.ok(fxl.cls('pair_a')->>'why' like '%course_url, official_url%' and fxl.cls('single_official')->>'why' like '%official_url stops%' and fxl.cls('single_official')->>'why' not like '%course_url%',
                 'after: the locked fields are named in why (course_url, official_url; or official_url alone)');
  perform fxl.ok(fxl.cls('pair_a')->>'next_action' like '%a lock is never bypassed%' and fxl.cls('pair_a')->>'next_at' is null and (fxl.cls('pair_a')->>'technical')::boolean,
                 'after: the next action is a person (Layer 4) or a Platform Admin lifting the lock; no scheduled time; the item stays a technical hold');
  -- an entry_requirements lock still blocks (unchanged)
  perform fxl.ok(fxl.cls('entry_req')->>'class' = 'human_assisted' and fxl.cls('entry_req')->>'why' = 'the course''s entry requirements are locked by hand' and fxl.lockrefused('entry_req'),
                 'after: a lock on entry_requirements still blocks, with its own wording, and D-R2 refuses it');
  -- positive: unlocked, and a lock on a field D-R2 does not list, are still eligible and pass D-R2
  perform fxl.ok((fxl.cls('unlocked')->>'eligible')::boolean and (fxl.dr2('unlocked')->>'ok')::boolean, 'after: an unlocked eligible item is still eligible and passes D-R2');
  perform fxl.ok((fxl.cls('other_field')->>'eligible')::boolean and (fxl.dr2('other_field')->>'ok')::boolean, 'after: a lock on a field D-R2 does not list (tuition) leaves the item eligible and D-R2 allows it');
  -- every other class keeps its place (the class moves only from the two eligible classes)
  perform fxl.ok(fxl.cls('pair_rowlimit')->>'class' = 'row_limit' and fxl.cls('pair_ready')->>'class' = 'ready' and fxl.cls('pair_stale')->>'class' = 'stale' and fxl.cls('pair_human')->>'class' = 'human_assisted',
                 'after: a locked row-limit, ready, stale and human_assisted item keep their class');
end $$;
-- A2 no other item changed: class, eligibility and condition key as before the migration, apart from the three locked eligible cases and the changed_conditions case
do $$ declare v_diff text; begin
  select string_agg(c.k, ',' order by c.k) into v_diff
    from fxl.before b join lateral (select security.aer_recovery_rule_v1(b.item) r) n on true join fxl.cases c on c.item = b.item
   where b.cls is distinct from n.r->>'class' or b.ckey is distinct from n.r->>'condition_key' or b.eligible is distinct from (n.r->>'eligible')::boolean;
  perform fxl.ok(v_diff = 'pair_a,pair_b,pair_changed,single_official', 'after: among the cases only the four locked eligible ones changed class and condition key (' || coalesce(v_diff, 'none') || ')');
  perform fxl.ok(not exists (select 1 from fxl.before b join lateral (select security.aer_recovery_rule_v1(b.item) r) n on true
                              where not exists (select 1 from fxl.cases c where c.item = b.item)
                                and (b.cls is distinct from n.r->>'class' or b.ckey is distinct from n.r->>'condition_key' or b.eligible is distinct from (n.r->>'eligible')::boolean)),
                 'after: none of the other ' || (select count(*) from fxl.before) || ' waiting items changed class, eligibility or condition key');
end $$;
-- A3 the property over every waiting course entry read: never eligible by the rule while D-R2 refuses for a lock
do $$ declare v_bad int; v_n int; begin
  select count(*) into v_n from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code = 'course_entry_first_read' and (security.aer_recovery_rule_v1(i.id)->>'eligible')::boolean;
  select count(*) into v_bad from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code = 'course_entry_first_read' and (security.aer_recovery_rule_v1(i.id)->>'eligible')::boolean
     and coalesce(security.course_entry_correction_check_v1(i.id, i.entity_id, (select pg.url from pipeline.coverage_course_pages pg where pg.course_id = i.entity_id))->>'why', '') like '%manual lock%';
  perform fxl.ok(v_bad = 0 and v_n > 0, 'after: of ' || v_n || ' eligible items none is refused by D-R2 for a lock');
end $$;
-- A4 the held step no longer spends a scan on a lock: it records the class, and the lock is not removed
do $$ declare v_o text; v_locks int; begin
  begin
    insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value) values ('pipeline', 'aer.schedule_held_scan', 'scan', 'number', '1000'::jsonb)
      on conflict (toolset_key, key) do update set value = excluded.value;
    select outcome into v_o from security.aer_schedule_held_v1(1000) h where h.item_id = (select item from fxl.cases where k = 'pair_a');
    raise exception 'fx_rollback';
  exception when others then if sqlerrm <> 'fx_rollback' then raise; end if; end;
  perform fxl.ok(v_o like 'held, not read again: human_assisted%', 'after: the held step records the locked item as "' || left(coalesce(v_o, '?'), 90) || '..." and does not ask D-R2');
  select count(*) into v_locks from pipeline.manual_locks;
  perform fxl.ok(v_locks = (select n from fxl.locks_before), 'after: no lock was removed, added or changed by the migration (' || v_locks || ' locks)');
end $$;
-- A5 the rule follows the setting D-R2 reads (rolled back): both directions, and the entry_requirements floor
do $$ begin
  begin
    update pipeline.platform_toolset_settings set value = '["entry_requirements"]'::jsonb where toolset_key = 'pipeline' and key = 'entry.supersede_lock_fields';
    perform fxl.ok((fxl.cls('pair_a')->>'eligible')::boolean and not fxl.lockrefused('pair_a') and (fxl.dr2('pair_a')->>'ok')::boolean,
                   'setting without the page fields: the rule makes the page-lock item eligible again and D-R2 allows it (they still agree; the Platform Admin decides, not this change)');
    update pipeline.platform_toolset_settings set value = '[]'::jsonb where toolset_key = 'pipeline' and key = 'entry.supersede_lock_fields';
    perform fxl.ok((fxl.cls('pair_a')->>'eligible')::boolean and fxl.cls('entry_req')->>'class' = 'human_assisted',
                   'empty setting: page locks block neither; an entry_requirements lock still stops the rule (the floor: never less strict than before)');
    update pipeline.platform_toolset_settings set value = '["course_url"]'::jsonb where toolset_key = 'pipeline' and key = 'entry.supersede_lock_fields';
    perform fxl.ok(fxl.cls('pair_a')->>'why' like '%course_url stops%' and not (fxl.cls('pair_a')->>'eligible')::boolean and (fxl.cls('single_official')->>'eligible')::boolean and not fxl.lockrefused('single_official'),
                   'setting with course_url only: the pair is held for course_url alone; a lock on official_url alone is eligible and D-R2 allows it');
    raise exception 'fx_rollback';
  exception when others then if sqlerrm <> 'fx_rollback' then raise; end if; end;
  perform fxl.ok(security.toolset_setting('pipeline', 'entry.supersede_lock_fields') = '["entry_requirements", "course_url", "official_url"]'::jsonb, 'the setting is back to the live value after the rolled-back checks');
end $$;
-- A6 the lane and the measure: the next hourly run of the lane records exactly the four, parks them as human input with the lock named, and the measure's eligible count falls by four
do $$ declare v_run jsonb; v_el int; begin
  v_run := security.aer_technical_recovery_v1();
  perform fxl.ok((v_run->'by_class') = '{"human_assisted": 4}'::jsonb, 'after: the next run of the lane reports exactly 4 changed items, all human_assisted (' || (v_run->>'by_class') || '); every other item is unchanged and not reported again');
  perform fxl.ok((select count(*) from fxl.cases c join pipeline.work_items w on w.lane = 'aer_technical' and w.entity = c.item::text and w.work_kind = 'l4_item'
                   where c.k in ('pair_a', 'pair_b', 'single_official', 'pair_changed') and w.failure_class = 'aer_human_input' and w.stage = 'parked' and w.unresolved_blocker->>'next_action' like '%never bypassed%') = 4,
                 'after: the four lane items moved from aer_reread_eligible to aer_human_input (parked, next action named)');
  select (security.progress_measure_v1('aer_technical_correction', now() - interval '1 day')->>'eligible')::int into v_el;
  perform fxl.ok(v_el = (select n from fxl.measure_before) - 4, 'after: the aer_technical_correction measure counts ' || v_el || ' eligible, ' || (select n from fxl.measure_before) || ' before: only items D-R2 can accept are counted');
end $$;
\endif
