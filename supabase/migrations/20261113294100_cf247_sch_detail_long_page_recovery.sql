-- CF-247 F-SCH long-page recovery (Platform Admin S2-Scholarship directive 13 Nov 2026 §2; Operating Model v1.19 S2-Scholarship 2).
-- 77 active scholarships have no version 3 reading: their whole-page reading was cut at the answer limit or the model returned no answer, three
-- tries each (277 calls, US$0.16; 50 cut and 44 unanswered overlap within the 77, one per page). Whole-page retries are not repeated. Instead each
-- gets ONE recovery item that the worker (coverage-sweep v0.83.0, sch-extract.ts RECOVERY_VARIANT sectioned-v1) reads from the stored official
-- copy as the award's own section plus its linked terms page, in two smaller calls merged into the same version 3 answer. The answer goes through
-- the same record and apply path as any detail reading (svc_scholarship_ai_record -> security.scholarship_detail_apply_v1: checked quotes only,
-- empty canonical fields only, never a locked one). Success is a new validated canonical field, not a call.
--   pipeline.scholarship_ai_queue.recovery    new column: the recovery variant of an item (null for every other item)
--   security.scholarship_detail_recovery_queue_v1(limit)   queues one sectioned-v1 item per active scholarship that has a stored page, no
--       version 3 reading, a failed version 3 detail item ended by a cut, empty or unreadable answer, and no recovery item yet; at most once
--       (a recovery item that fails its three tries is terminal and shown as such)
--   security.scholarship_detail_backfill_v1   also queues recovery items within the same limit (sch_detail.recovery_on)
--   public.svc_scholarship_ai_next             hands the worker the item's recovery variant and the recorded scholarship name
-- Settings: sch_detail.recovery_on (1), scholarship.recovery_section_chars (6,000), scholarship.recovery_linked_chars (4,000).
-- Replaces: security.scholarship_detail_backfill_v1(integer), public.svc_scholarship_ai_next(integer) (same names and signatures; md5-guarded
--   edits). Retires: the whole-page retry of the 77 (none is queued again).

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

alter table pipeline.scholarship_ai_queue add column if not exists recovery text;
comment on column pipeline.scholarship_ai_queue.recovery is
  'F-SCH long-page recovery variant of the item (sectioned-v1: the award''s own section of the stored page in two smaller calls); null for every other item.';

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values
 ('pipeline', 'sch_detail.recovery_on', 'Scholarship details: recover long pages in sections',
  '1: an active scholarship whose whole-page reading was cut or unanswered is read once more from its stored page as the award''s own section in two smaller calls. 0: no recovery item is queued.',
  'number', '1'::jsonb, 0, 1, 'on (1) or off (0)', 1431, 'F-SCH 13 Nov 2026 (S2-Scholarship directive §2): 77 long-page failures', 'Scholarship details', 'security.scholarship_detail_backfill_v1, security.scholarship_detail_recovery_queue_v1'),
 ('pipeline', 'scholarship.recovery_section_chars', 'Scholarship details recovery: award section length',
  'How much of the stored page, from just before the award name, a recovery reading sends.',
  'number', '6000'::jsonb, 1000, 14000, 'characters', 1432, 'F-SCH 13 Nov 2026: bounded award section', 'Scholarship details', 'worker coverage-sweep v0.83.0 (mode scholarship_ai, recovery items)'),
 ('pipeline', 'scholarship.recovery_linked_chars', 'Scholarship details recovery: linked terms page length',
  'How much of the linked eligibility or terms page a recovery reading sends.',
  'number', '4000'::jsonb, 0, 8000, 'characters', 1433, 'F-SCH 13 Nov 2026: bounded linked terms', 'Scholarship details', 'worker coverage-sweep v0.83.0 (mode scholarship_ai, recovery items)')
on conflict (toolset_key, key) do nothing;

create or replace function security.scholarship_detail_recovery_queue_v1(p_limit integer)
returns integer language plpgsql security definer set search_path = '' as $$
declare a record; n int;
begin
  if security.pipeline_num_v1('sch_detail.recovery_on', 1) < 1 or coalesce(p_limit, 0) < 1 then return 0; end if;
  select * into a from security.scholarship_ai_active_v1();
  if a.model_code is null or coalesce(a.prompt_version, 0) < 3 then return 0; end if;
  insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, scholarship_id, provider_id, url, storage_path, recovery)
  select a.model_code, a.prompt_version, 'detail', s.id, s.provider_id, coalesce(sp.final_url, sp.url, s.source_url), ev.storage_path, 'sectioned-v1'
    from scholarship.scholarships s
    join pipeline.scholarship_pages sp on sp.scholarship_id = s.id
    join lateral (select x.storage_path from pipeline.evidence_artifacts x where x.id in (sp.evidence_id, s.evidence_id) and x.storage_path is not null order by (x.id = sp.evidence_id) desc limit 1) ev on true
   where s.lifecycle_status = 'active'
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)
     and not security.third_party_host_v1(coalesce(sp.final_url, sp.url, s.source_url))
     and not exists (select 1 from pipeline.scholarship_ai_extractions x where x.scholarship_id = s.id and x.prompt_version >= 3 and x.error is null)
     and exists (select 1 from pipeline.scholarship_ai_extractions x where x.scholarship_id = s.id and x.prompt_version >= 3
                  and (x.error like 'held_partial: output_truncated%' or x.error like 'no_answer%' or x.error like 'unreadable_answer%'))
     and not exists (select 1 from pipeline.scholarship_ai_queue q where q.scholarship_id = s.id and (q.state in ('queued', 'leased') or q.recovery is not null))
   order by (s.publication_status = 'published') desc, s.updated_at desc
   limit p_limit;
  get diagnostics n = row_count;
  return n;
end $$;
comment on function security.scholarship_detail_recovery_queue_v1(integer) is
  'F-SCH long-page recovery: one sectioned-v1 detail item per active scholarship whose version 3 readings were all cut, empty or unreadable; at most once.';
revoke all on function security.scholarship_detail_recovery_queue_v1(integer) from public, anon, authenticated;

select pg_temp.edit_n('security.scholarship_detail_backfill_v1(integer)', 'f830adfdff8846de51f8e695bdb8d525', array[
  array[$o$  get diagnostics n = row_count;
  return n;$o$,
        $n$  get diagnostics n = row_count;
  -- 20261113294100: long-page recovery items within the same limit
  n := n + security.scholarship_detail_recovery_queue_v1(greatest(p_limit - n, 0));
  return n;$n$]
], array[1]);

select pg_temp.edit_n('public.svc_scholarship_ai_next(integer)', '709ad0f93b16e99f8962e85671f0b291', array[
  array[$o$'run_kind', u.run_kind, 'url', u.url,$o$,
        $n$'run_kind', u.run_kind, 'url', u.url, 'recovery', u.recovery,
           'scholarship_name', (select s.name from scholarship.scholarships s where s.id = u.scholarship_id),$n$]
], array[1]);
