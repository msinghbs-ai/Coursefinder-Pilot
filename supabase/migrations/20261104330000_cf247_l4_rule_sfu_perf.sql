-- CF-247 Layer 4 course-link rule executor: sfu_no_term (strict) could not run (Integration Controller, 4 Nov 2026 00:16 and 00:26 AEDT: even a
-- counting call with limit 10 reached the statement time-out).
-- Why: security.layer4_course_link_rule_execute_v1 chose its items from security.layer4_course_link_rule_validate_v1(rule, null), which validates
--   every waiting item of the rule before the limit applies; for a strict rule each validation calls the whole binding check
--   (security.course_page_check_v1: provider-wide shared-page, sibling-title, campus, other-provider and code scans) only to read two level lists.
-- What:
--   1 security.layer4_rule_level_v1(course, url): the binding check's level reading alone, the same settings (binding.level_patterns) on the same
--     inputs (the course title and study level; the page address and its read title), so its answer is the one course_page_check_v1 gives in
--     checks.course_levels and checks.page_levels. A few indexed reads per item.
--   2 The validator (md5-guarded edit) reads the course level through it, once per item (its row set is materialised: inlined, the reading ran
--     again for each of the five places its result is used, so each strict item paid for five whole binding checks). The check is unchanged: a strict rule's item still fails, with its
--     reason, unless the course level is found and is on the page; nothing passes without it.
--   3 The executor (md5-guarded edit) first takes the rule's waiting item ids, cheaply and up to the limit (items no run of this rule has looked at
--     first, then the longest since looked at), then validates each item on its own. A run stops taking new items once it has used its time budget
--     (layer4.rule_execute_time_budget_s, below the 8 s statement time-out); the items it did not reach stay waiting, are reported as not_reached
--     and come first in the next call. One slow item cannot stop the rest of the queue: it is looked at once and goes to the back.
-- Replaces: the executor's selection through the validator over the whole rule group; the strict rule's level reading through
--   security.course_page_check_v1 (same names; md5-guarded edits; course_page_check_v1 itself is not edited and stays the binding check)
-- Retires: nothing
-- Nothing is dropped, deleted or switched on. No spend. No rule is executed here. Consumer API untouched (G3).
-- md5 (pg_get_functiondef) before (live, read 4 Nov 2026 00:29 AEDT) -> after:
--   security.layer4_course_link_rule_validate_v1(text,uuid)            31bd052cb7161008ef9452bd24eb0e75 -> 3a5d088e4aaf3ad1e1a5460524a2e70a
--   security.layer4_course_link_rule_execute_v1(text,integer,boolean)  86e1089a5e93e1e2cce9a0ffd29aa22b -> 85c991e7b626e07f9777f7a65249fd81

do $g$
begin
  if to_regprocedure('security.course_page_check_v1(uuid,text,text,text)') is null then raise exception 'security.course_page_check_v1 (E16) must exist'; end if;
  if to_regclass('pipeline.layer4_course_link_rule_run_items') is null then raise exception 'pipeline.layer4_course_link_rule_run_items (v2.15.448) must exist'; end if;
end $g$;

-- settings (G2; Settings > Pipeline settings, section Layer 4)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'layer4.rule_execute_time_budget_s', 'Layer 4 rules: time one executor call may spend',
  'A rule executor call stops taking new items after this many seconds; the items it did not reach stay waiting and come first in the next call. Keep it below the 8 second statement time-out.',
  'number', to_jsonb(5), 1, 7, 'seconds', 1239, 'Layer 4 readiness', 'security.layer4_course_link_rule_execute_v1',
  'CF-247: sfu_no_term reached the statement time-out (4 Nov 2026 00:16)')
on conflict do nothing;

-- 1 the level reading alone ----------------------------------------------------------------------------------------------------------------
create or replace function security.layer4_rule_level_v1(p_course uuid, p_url text) returns jsonb
language sql stable security definer set search_path to '' as $function$
-- The binding check's level reading (security.course_page_check_v1, lv), alone: the levels of binding.level_patterns found in the course title and
-- study level, and in the page address path and its read title. {verdict, checks: {course_levels, page_levels}}. Same inputs, same answer.
  with s as (select coalesce(security.toolset_setting('pipeline', 'binding.level_patterns'), '[]'::jsonb) lv),
  c as (select co.id, co.provider_id, lower(co.canonical_title) || ' ' || coalesce(replace(sl.code, '_', ' '), '') ltext
          from catalogue.courses co left join ref.study_levels sl on sl.id = co.study_level_id where co.id = p_course),
  u as (select lower(coalesce(substring(p_url from '^https?://[^/?#]+(/[^?#]*)'), '/')) path,
               lower(coalesce((select coalesce(nullif(g.candidates->>'page_title', ''), g.candidates->>'h1') from pipeline.coverage_course_pages g join c on g.provider_id = c.provider_id
                                where (g.url = p_url or g.candidates->>'final_url' = p_url) and g.read_status = 'read'
                                  and coalesce(nullif(g.candidates->>'page_title', ''), g.candidates->>'h1') is not null limit 1), '')) title),
  lv as (select array(select distinct split_part(e, '=', 1) from s, c, jsonb_array_elements_text(s.lv) e where c.ltext ~* substr(e, strpos(e, '=') + 1) order by 1) course_lv,
                array(select distinct split_part(e, '=', 1) from s, u, jsonb_array_elements_text(s.lv) e where (u.path || ' ' || u.title) ~* substr(e, strpos(e, '=') + 1) order by 1) page_lv)
  select jsonb_build_object('verdict', case when cardinality(lv.course_lv) > 0 and lv.course_lv && lv.page_lv then 'level on the page' else 'level not confirmed' end,
                            'checks', jsonb_build_object('course_levels', to_jsonb(lv.course_lv), 'page_levels', to_jsonb(lv.page_lv)))
    from lv
$function$;
revoke all on function security.layer4_rule_level_v1(uuid, text) from public, anon, authenticated;

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int; v_old text; v_new text;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    -- fixed: line endings are normalised, so the edit applies the same however the text arrives
    v_old := replace(p_edits[i][1], chr(13), ''); v_new := replace(p_edits[i][2], chr(13), '');
    v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, v_old, v_new);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': applied';
end $f$;

-- 2 the validator reads the level alone ------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.layer4_course_link_rule_validate_v1(text,uuid)', '31bd052cb7161008ef9452bd24eb0e75', '3a5d088e4aaf3ad1e1a5460524a2e70a',
  array[
    array['-- check''s level reading, security.course_page_check_v1)', '-- check''s level reading, read alone by security.layer4_rule_level_v1)'],
    array['case when m.strict then security.course_page_check_v1(m.course_id, m.target_url) end chk', 'case when m.strict then security.layer4_rule_level_v1(m.course_id, m.target_url) end chk'],
    -- read once per item: inlined, the level reading ran again for every place its result is used (five times per item)
    array[E'\n  e as (\n', E'\n  e as materialized (\n']
  ], array[1, 1, 1]);

-- 3 the executor takes item ids first, then validates each, within a time budget ----------------------------------------------------------------
select pg_temp.edit_once('security.layer4_course_link_rule_execute_v1(text,integer,boolean)', '86e1089a5e93e1e2cce9a0ffd29aa22b', '85c991e7b626e07f9777f7a65249fd81',
  array[
    array['        v_caller uuid := auth.uid(); v_lock int; v_by jsonb := ''{}''::jsonb; v_why text;',
          '        v_caller uuid := auth.uid(); v_lock int; v_by jsonb := ''{}''::jsonb; v_why text; v_t0 timestamptz := clock_timestamp(); v_left int := 0;'],
    array['  for v in select x.item_id from security.layer4_course_link_rule_validate_v1(r.code, null) x
            order by x.item_id limit least(greatest(coalesce(p_limit, 0), 0), security.pipeline_num_v1(''layer4.rule_execute_batch'', 50)::int) loop
    v_n := v_n + 1;',
          '  -- the rule''s waiting items, ids only (validation is per item, below): items no run of this rule has looked at first, then the longest since
  for v in select i.id item_id from pipeline.layer4_review_items i join catalogue.courses c on c.id = i.entity_id
            where c.provider_id = r.provider_id and i.status = ''pending'' and i.field_code = ''official_course_url'' and i.escalation_reason ilike r.reason_like
            order by (select max(ri.at) from pipeline.layer4_course_link_rule_run_items ri join pipeline.layer4_course_link_rule_runs rr on rr.id = ri.run_id
                       where ri.item_id = i.id and rr.rule = r.code) asc nulls first, i.id
            limit least(greatest(coalesce(p_limit, 0), 0), security.pipeline_num_v1(''layer4.rule_execute_batch'', 50)::int) loop
    -- the call''s time budget: items not reached stay waiting and come first next time
    if clock_timestamp() - v_t0 > make_interval(secs => security.pipeline_num_v1(''layer4.rule_execute_time_budget_s'', 5)) then v_left := v_left + 1; continue; end if;
    v_n := v_n + 1;'],
    array['failed = v_fail,
         result = jsonb_build_object(''failed_by_reason'', v_by) where id = v_run;',
          'failed = v_fail,
         result = jsonb_build_object(''failed_by_reason'', v_by, ''not_reached'', v_left, ''seconds'', round(extract(epoch from clock_timestamp() - v_t0)::numeric, 1)) where id = v_run;'],
    array['''failed'', v_fail, ''failed_by_reason'', v_by, ''approval_ref'', r.approval_ref), v_caller);',
          '''failed'', v_fail, ''not_reached'', v_left, ''failed_by_reason'', v_by, ''approval_ref'', r.approval_ref), v_caller);'],
    array['''failed'', v_fail,
                            ''failed_by_reason'', v_by,', '''failed'', v_fail, ''not_reached'', v_left,
                            ''failed_by_reason'', v_by,']
  ], array[1, 1, 1, 1, 1]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.layer4_rule_level_v1', 'Layer 4', 'The binding check''s level reading alone, for strict course-link rules', 'active', '{}', '20261104330000')
on conflict do nothing;
