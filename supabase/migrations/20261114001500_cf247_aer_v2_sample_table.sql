-- CF-247 AER v2 reader: the page selector runs well inside the worker's 8 s statement limit (Platform Admin 14 Nov 2026 00:10, item 1: "fix the 8.9s
--   cold-start page selector so it runs well under the 8s DB limit").
-- Evidence (13 Nov 2026 23:50-00:05 AEDT): public.svc_aer_v2_shadow_next failed with "canceling statement due to statement timeout" (worker call 700433);
--   security.aer_v2_shadow_candidates_v1 measured 8.9 s cold, 4.6 s and 1.2 s warm. It rebuilt the whole sample on every call: the AER-eligible pool,
--   pipeline.aer_labelled_rows_v1 (2.4 s on its own) and the gate_incomplete lane, then ranked all of them.
-- What:
--   1. pipeline.aer_v2_sample: the ranked sample (course, lane, rank), built by security.aer_v2_sample_refresh_v1() outside the worker's call (the
--      aer-v2-shadow job at :08 and :38 refreshes it when older than aer.v2_sample_refresh_minutes; this change builds it once). Courses that leave the
--      sample are marked in_sample = false, never deleted.
--   2. security.aer_v2_shadow_candidates_v1 reads the stored sample: the next courses in rank order that still have a bound, stored official page and
--      are not yet read by the prompt version (the same tries rule as before). Same signature, same columns, same order of lanes.
--   3. security.aer_v2_shadow_fire_v1 (md5-guarded edit): refreshes the sample when it is older than the setting, then fires as before.
-- The v2 reader stays paused (aer.v2_shadow_on 0, Platform Admin 14 Nov 2026 00:10); nothing here reads, spends or admits. The 1,912-page queue and
--   every page's tries are unchanged (the tries rule reads pipeline.aer_v2_shadow_results exactly as before).
-- Guards: G1 (no new job; the existing aer-v2-shadow job refreshes), G2 (refresh age is a setting), G3 (no consumer API object), AER v1 frozen, nothing
--   deleted.
-- Live definitions this change replaces or edits (md5 of pg_get_functiondef, read 14 Nov 2026 00:20 AEDT):
--   security.aer_v2_shadow_candidates_v1 9e2c10d3cf4c412b05cde408bea8604d (replaced), security.aer_v2_shadow_fire_v1 d5abb3cd4e78834c9406ffa7f8bd26fe (edited).
-- Replaces: the per-call sample build in security.aer_v2_shadow_candidates_v1. Retires: nothing.

do $g$ begin
  if md5(pg_get_functiondef('security.aer_v2_shadow_candidates_v1(text,integer)'::regprocedure)) <> '9e2c10d3cf4c412b05cde408bea8604d' then
    raise exception 'live security.aer_v2_shadow_candidates_v1 differs from the definition this change replaces';
  end if;
end $g$;

create table if not exists pipeline.aer_v2_sample (
  course_id uuid primary key,
  lane smallint not null,
  priority bigint,
  provider_country text,
  sample_rank integer not null,
  in_sample boolean not null default true,
  refreshed_at timestamptz not null default now()
);
comment on table pipeline.aer_v2_sample is 'AER v2 reader: the ranked course sample the shadow reader takes pages from (lane 0 gate_incomplete Layer 4 reads, 1 courses with a person''s decision, 2 priority providers, 3 the rest; priority is the provider''s place in aer.v2_shadow_priority_providers), built by security.aer_v2_sample_refresh_v1 outside the worker''s call so the page selector stays inside the 8 s statement limit. A course that leaves the sample is marked in_sample = false, never deleted.';
create index if not exists aer_v2_sample_rank on pipeline.aer_v2_sample(sample_rank) where in_sample;
create index if not exists aer_v2_shadow_results_version_course on pipeline.aer_v2_shadow_results(prompt_version, course_id);

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'aer.v2_sample_refresh_minutes', 'Entry requirements v2: rebuild the reader sample after',
  'The aer-v2-shadow job rebuilds the ranked course sample (pipeline.aer_v2_sample) when it is older than this, before it fires the reader. The worker''s page selector only reads the stored sample.',
  'number', to_jsonb(60), 5, 1440, 'minutes', 1545, 'Entry requirements', 'security.aer_v2_shadow_fire_v1 (job aer-v2-shadow), security.aer_v2_sample_refresh_v1',
  'Platform Admin 14 Nov 2026 00:10 item 1: the page selector timed out at 8.9 s')
on conflict (toolset_key, key) do nothing;

create or replace function security.aer_v2_sample_refresh_v1() returns jsonb
language plpgsql security definer set search_path to '' as $f$
-- one upsert stamps every course in the sample with this transaction's now(); a course left with an older stamp has left the sample
declare v_t0 timestamptz := clock_timestamp(); v_in int; v_out int;
begin
  insert into pipeline.aer_v2_sample as t(course_id, lane, priority, provider_country, sample_rank, in_sample, refreshed_at)
  with cfg as materialized (select security.pipeline_num_v1('aer.v2_shadow_sample', 2000) sample_size),
  pri as (select x.id, x.ord from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.v2_shadow_priority_providers'), '[]'::jsonb)) with ordinality x(id, ord)),
  pool as (select c.id course_id, pri.ord priority, e.country provider_country
             from catalogue.courses c
             join security.aer_eligible_v1() e on e.provider_id = c.provider_id
             join pipeline.coverage_course_pages g on g.course_id = c.id and g.status = 'bound'
             join pipeline.evidence_artifacts a on a.id = g.evidence_id and a.storage_path is not null
             left join pri on pri.id = c.provider_id::text
            where c.lifecycle_status = 'active' and c.open_to_international is not false),
  lab as materialized (select distinct l.course_id from pipeline.aer_labelled_rows_v1 l where l.course_id is not null),
  -- lane 0: courses whose v1 read waits in Layer 4 held as gate_incomplete (one pass over the decisions, newest per item)
  gi as materialized (select distinct l.course_id from (
                        select distinct on (a.review_item_id) a.review_item_id, a.reason_code, i.entity_id course_id
                          from pipeline.layer4_review_items i join pipeline.aer_machine_admissions a on a.review_item_id = i.id
                         where i.field_code = 'course_entry_first_read' and i.status = 'pending' and i.entity_type = 'course'
                         order by a.review_item_id, a.updated_at desc) l
                       where l.reason_code = 'gate_incomplete'),
  laned as (select pool.*, case when exists (select 1 from gi where gi.course_id = pool.course_id) then 0
                                when exists (select 1 from lab where lab.course_id = pool.course_id) then 1
                                when pool.priority is not null then 2 else 3 end lane from pool),
  ranked as (select laned.*, row_number() over (partition by laned.lane order by laned.priority nulls last, md5(laned.course_id::text)) lane_rank from laned),
  sample as (select ranked.*, row_number() over (order by (ranked.lane = 3), (ranked.lane > 0), ranked.lane_rank, ranked.lane) sample_rank from ranked)
  select s.course_id, s.lane, s.priority, s.provider_country, s.sample_rank, true, now() from sample s cross join cfg where s.sample_rank <= cfg.sample_size
  on conflict (course_id) do update set lane = excluded.lane, priority = excluded.priority, provider_country = excluded.provider_country,
                                        sample_rank = excluded.sample_rank, in_sample = true, refreshed_at = excluded.refreshed_at;
  get diagnostics v_in = row_count;
  update pipeline.aer_v2_sample t set in_sample = false, refreshed_at = now() where t.in_sample and t.refreshed_at < now();
  get diagnostics v_out = row_count;
  return jsonb_build_object('in_sample', v_in, 'left_sample', v_out,
                            'lanes', (select jsonb_object_agg(z.lane, z.n) from (select s.lane, count(*) n from pipeline.aer_v2_sample s where s.in_sample group by 1) z),
                            'ms', (extract(epoch from clock_timestamp() - v_t0) * 1000)::int);
end $f$;
comment on function security.aer_v2_sample_refresh_v1() is 'AER v2 reader: rebuilds pipeline.aer_v2_sample (the ranked course sample: gate_incomplete reads first, then courses with a person''s decision, priority providers, the rest), outside the worker''s call. Marks courses that left the sample, never deletes.';
revoke all on function security.aer_v2_sample_refresh_v1() from public, anon, authenticated;

create or replace function security.aer_v2_shadow_candidates_v1(p_version text, p_limit integer)
 returns table(course_id uuid, provider_id uuid, title text, level text, provider text, provider_country text, url text, evidence_id uuid, content_hash text, storage_path text, priority bigint, sample_rank bigint)
 language sql stable security definer set search_path to '' as $function$
  -- 14 Nov 2026 (Platform Admin 00:10 item 1): reads the stored sample (pipeline.aer_v2_sample, built by security.aer_v2_sample_refresh_v1) in rank order;
  -- only the current page and the tries rule are looked up per course, so the call stays well inside the worker's 8 s statement limit
  with cfg as materialized (select security.pipeline_num_v1('aer.v2_shadow_tries', 2) tries,
                            coalesce(security.toolset_setting('pipeline', 'aer.retry_now_error_pattern') #>> '{}', '') refused),
  done as materialized (select r.course_id from pipeline.aer_v2_shadow_results r cross join cfg where r.prompt_version = p_version
                         group by r.course_id, cfg.tries having count(*) filter (where r.error is null) > 0 or count(*) filter (where r.error is null or cfg.refused = '' or r.error !~* cfg.refused) >= cfg.tries)
  select c.id, c.provider_id, c.canonical_title, sl.name, coalesce(p.display_name, p.canonical_name), s.provider_country,
         g.url, a.id, a.content_hash, a.storage_path, s.priority, s.sample_rank::bigint
    from pipeline.aer_v2_sample s
    join catalogue.courses c on c.id = s.course_id and c.lifecycle_status = 'active'
    join catalogue.providers p on p.id = c.provider_id
    join pipeline.coverage_course_pages g on g.course_id = c.id and g.status = 'bound'
    join pipeline.evidence_artifacts a on a.id = g.evidence_id and a.storage_path is not null
    left join ref.study_levels sl on sl.id = c.study_level_id
   where s.in_sample and not exists (select 1 from done where done.course_id = s.course_id)
   order by s.sample_rank
   limit greatest(coalesce(p_limit, 0), 0)
$function$;
comment on function security.aer_v2_shadow_candidates_v1(text, integer) is 'AER v2 reader: the next courses of the stored sample (pipeline.aer_v2_sample) in rank order whose official page is bound and stored and that the prompt version has not read (a failed read is offered again until it has aer.v2_shadow_tries results). Same columns as before.';

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('security.aer_v2_shadow_fire_v1()', 'd5abb3cd4e78834c9406ffa7f8bd26fe', array[
  array[$o$  if not security.ai_use_allowed_v1('entry_matrix') then return jsonb_build_object('on', true, 'ai', security.ai_use_refusal_v1('entry_matrix')); end if;$o$,
        $n$  if not security.ai_use_allowed_v1('entry_matrix') then return jsonb_build_object('on', true, 'ai', security.ai_use_refusal_v1('entry_matrix')); end if;
  -- 14 Nov 2026: the sample is rebuilt here (no statement limit), never in the worker's call
  if coalesce((select max(s.refreshed_at) from pipeline.aer_v2_sample s), '-infinity') < now() - make_interval(mins => security.pipeline_num_v1('aer.v2_sample_refresh_minutes', 60)::int) then
    perform security.aer_v2_sample_refresh_v1();
  end if;$n$]
], array[1]);

update pipeline.platform_toolset_settings set used_by = 'security.aer_v2_sample_refresh_v1 (job aer-v2-shadow), security.aer_v2_shadow_candidates_v1'
 where toolset_key = 'pipeline' and key in ('aer.v2_shadow_sample', 'aer.v2_shadow_priority_providers');

-- build the sample once
select security.aer_v2_sample_refresh_v1();

-- post-checks: the selector is fast, the lanes are as before, the reader is still paused
do $c$
declare t0 timestamptz := clock_timestamp(); v_ms int; v_lane0 int;
begin
  perform count(*) from security.aer_v2_shadow_candidates_v1('aer-v2-course-v2', 40);
  v_ms := (extract(epoch from clock_timestamp() - t0) * 1000)::int;
  if v_ms > 2000 then raise exception 'post-check: the page selector took % ms (must stay well under 8 s)', v_ms; end if;
  select count(*) into v_lane0 from pipeline.aer_v2_sample where in_sample and lane = 0;
  if v_lane0 < 1 then raise exception 'post-check: lane 0 (gate_incomplete) is empty'; end if;
  if security.pipeline_num_v1('aer.v2_shadow_on', 0) <> 0 then raise exception 'post-check: the v2 reader must stay paused (Platform Admin 14 Nov 00:10)'; end if;
end $c$;
