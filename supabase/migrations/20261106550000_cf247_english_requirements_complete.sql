-- CF-247 English requirements: faculty and course-group tables, provider scope and "why no English rule" (Platform Admin decision 6 Nov 2026 09:44 §3-§5,
-- admin docs/platform/2026-11-06-release-and-enrichment-decisions-0944.md). Agent H, branch cf247-english-requirements-complete.
-- Plan: admin docs/platform/work-packages/2026-11-06-english-requirements-implementation-plan.md. Compatibility record: docs/english-requirements.md.
-- Why: 30,568 English rows are published and both routes (university policies, course-page reading) are automated, but the capability has plateaued. A university whose
--   English rule is a faculty or course-group table (UNSW: 658 courses without English) has no default, so the policy parser reports the table and declines it, and the
--   operator cannot see, for any provider without a rule, which page was tried, what it gave, why there is no rule and when it is tried next.
-- What (decisions of 6 Nov 2026 §3):
--   D1 provider scope: central.english_provider_types (shipped ["*"], today's behaviour: the route already serves every provider type), read by central_pages_attach_v1 and
--      central_ai_enqueue_v1 through security.english_provider_in_scope_v1. Nothing approved is withdrawn when it changes.
--   D2 every faculty or course-group rule needs a person: a reading with group rules is filed as status proposed (parser v0.3.0 `groups`), policy_auto_approve_v1 never approves
--      one (and never closes one), and a group reaches a course only through a binding a Platform Admin sets (admin_provider_english_groups_set_v1: ASCED fields of study
--      and/or a title pattern, logged). There is no setting that approves groups automatically.
--   D3 non-university central English search: built and SWITCHED OFF (central.english_search_non_university = 0; batch.english_search_non_university). Nothing is queued,
--      searched or spent while it is 0; no credit decision is made by this change.
--   D5 stored-page reparsing reuses job policy-add-tests (mode provider_facts_add_tests, new reparse_limit from batch.policy_reparse): svc_provider_policy_reparse_next lists
--      stored English pages whose latest reading gave no values (or was rejected as one faculty row) and that the current parser has not read. No Firecrawl, no AI, no new job.
--   D6 VET-level English stays out (courses at levels the policy does not cover stay held).
--   Plan and apply: security.provider_english_plan_v1 gains a `group` plan after the held cases and before the level default, so the existing precedence is unchanged: a course's
--      own reading is never replaced (outcome differs / agrees / other_value / set_by_hand / in_review / waiting), a course the policy names keeps its own score, research and
--      double degrees stay held, and a course another approved policy of the university names (or groups) is not taken by this one. provider_english_apply_v1 writes group rows
--      through coverage_apply_course_v1 with source_requirement_key policy:<id>:<test> and a note naming the group.
--   Visibility (decision §5), existing Admin workspace only (Coverage › Attributes › English policies): public.admin_provider_english_status_read (stage, pages tried, last
--      reading, why there is no rule, next try, jobs, spend, proposals) and group counts in admin_provider_policies_read.
-- Consumer API: unchanged (G3). Rows go only into catalogue.course_english_requirements through coverage_apply_course_v1, as policy rows do today.
-- Replaces: public.svc_provider_policy_record, security.policy_auto_approve_v1, security.central_pages_attach_v1, security.central_ai_enqueue_v1, security.provider_english_plan_v1,
--   security.provider_english_apply_v1, public.admin_provider_policies_read, public.admin_provider_policy_decide, public.svc_provider_facts_search_next (each md5-guarded on its live
--   definition below, replaced in place with the old behaviour kept); the command of job policy-add-tests (one more argument).
-- Retires: nothing. (fee-schedule-etl's D162 English modes and the public.svc_english_table_* functions are not touched here: a separate housekeeping item once the live check is repeated.)
-- Nothing is dropped or deleted by this migration.
-- Deploy: apply outside :17 (policy-add-tests), :48 (central-attach) and the 10-minute marks of provider-english-defaults (3-59/10) and policy-auto-approve (5-59/10); a lock on
--   provider_policy_proposals makes it fail cleanly; reconcile the transaction and migration history before retrying. The governed deployment applies this migration
--   before deploying coverage-sweep v0.59.10 (parser provider-policy-v0.3.0), after the separately validated #894 release (Worker v0.59.9). Verify both live before acceptance.

-- 0 guards: every function this change replaces or relies on is the one the plan was written against ----------------------------------------------------
do $guard$
declare r record; v_md5 text;
begin
  for r in select * from (values
  ('public.svc_provider_policy_record(uuid,jsonb)', '16b04b3170fae3fc97a5c632d7111fe5'),
  ('security.policy_auto_approve_v1()', '7b8f780d78c439546bcd4fc29da3bdb3'),
  ('security.central_pages_attach_v1()', '0e930780d50cbb65bea581d25a583356'),
  ('security.central_ai_enqueue_v1(uuid)', 'e2cf9db03152405152d9a1edd94a9a67'),
  ('security.provider_english_plan_v1(uuid)', '60f5892657ef976634b12914d91f24a9'),
  ('security.provider_english_apply_v1(uuid)', '760c173d759c77e0cfa9fa8c04355e14'),
  ('public.admin_provider_policies_read(text,uuid)', 'fd6fdad2d073a4530d61e4f7d274ef31'),
  ('public.admin_provider_policy_decide(uuid,text,text)', '5ba211ffcec4397fdccc1d9a417a0c10'),
  ('public.svc_provider_facts_search_next(integer)', '14c68d372eb69d1487e5a887d4a81d20'),
  ('security.english_level_apply_v1(uuid,boolean)', '271a9600d80d8e6e3aa1e5644bd7ae80'),
  ('security.english_policy_in_force_v1(uuid,boolean)', '7add799eb55048372f61239f3648fcc3'),
  ('security.english_policy_in_force_all_v1(boolean)', 'bf32beb9bb284d4130101ffdaeb8eb40'),
  ('security.english_level_apply_all_v1(boolean)', 'c568deddebc50ce2482362f73e5e2af1'),
  ('security.provider_english_apply_all_v1()', 'a0d9a19695fd50416b65460b3149a2df'),
  ('security.provider_policy_refresh_one_v1(uuid)', 'c29c87dc0b8f024bd6f51c6ec0be47d9'),
  ('public.svc_provider_english_add_tests_v1(uuid,text,jsonb,text)', '5f8b4c1b36708c735bbf1ec902f4b0ea'),
  ('public.svc_provider_policy_add_tests_next(text,integer)', '4f4cf77f1101d92077957ff2534fb4c7'),
  ('public.admin_provider_english_propose(uuid,jsonb,text,text)', '436b0bec1a5fbf6430c03b1106fa8e17')
  ) g(sig, md5) loop
    select md5(pg_get_functiondef(to_regprocedure(r.sig))) into v_md5;
    if v_md5 is distinct from r.md5 then raise exception 'live % (md5 %) differs from the definition this change was written against (%)', r.sig, v_md5, r.md5; end if;
  end loop;
  if (select md5(command) from cron.job where jobname = 'policy-add-tests') is distinct from '4827953f23c896d5ae05b14dd4ca722f' then
    raise exception 'live policy-add-tests command differs from the one this change replaces';
  end if;
end $guard$;

-- 1 settings (G2) -------------------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'central.english_provider_types', 'Central English pages: provider types',
  'Which provider types the central English route serves: it attaches a found English page, searches again and sends a stored page to the AI reading only for these. ["*"] is every type (today''s behaviour, shipped value); a list of provider type codes (for example ["university"]) limits it. Policies already approved are never withdrawn by a change here.',
  'list', '["*"]'::jsonb, null, null, 'provider types', 1010, 'English policies', 'security.english_provider_in_scope_v1; security.central_pages_attach_v1; security.central_ai_enqueue_v1',
  'Platform Admin decision 6 Nov 2026 §3 D1: preserve today''s provider scope (universities and eligible non-university providers)'),
 ('pipeline', 'batch.policy_reparse', 'English policies: stored pages read again per run',
  'How many stored English pages the hourly policy-add-tests job reads again with the current policy parser (no Firecrawl, no AI). Only pages whose latest reading gave no values, or was rejected as one faculty row, and that the current parser has not read.',
  'number', to_jsonb(20), 0, 200, 'documents', 1011, 'English policies', 'job policy-add-tests; public.svc_provider_policy_reparse_next',
  'Platform Admin decision 6 Nov 2026 §3 D5: reuse the existing policy-add-tests job for stored-page reparsing'),
 ('pipeline', 'central.english_search_non_university', 'Central English pages: search providers that have none',
  '1: the central-attach job queues providers that have no central English page, no search and no rule (within central.english_provider_types) for a Firecrawl search inside their own website; the existing provider-facts job runs it within the central daily share. 0: nothing is queued or searched. Shipped 0: switching it on is a separate spending decision after a credit reconciliation.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1012, 'English policies', 'security.central_pages_attach_v1; public.svc_provider_facts_search_next',
  'Platform Admin decision 6 Nov 2026 §3 D3: built switched off; no activation and no credit spend without a separate spending decision'),
 ('pipeline', 'batch.english_search_non_university', 'Central English pages: providers queued per run when the search is on',
  'How many providers the hourly central-attach job queues for the central English search while central.english_search_non_university is 1 (largest by active courses first). Each search costs Firecrawl credits inside the central daily share.',
  'number', to_jsonb(10), 1, 100, 'providers', 1013, 'English policies', 'security.central_pages_attach_v1',
  'Platform Admin decision 6 Nov 2026 §3 D3: a small pilot size, used only when the switch is on')
on conflict (toolset_key, key) do nothing;

-- 2 helpers (new) ---------------------------------------------------------------------------------------------------------------------------------------
create or replace function security.english_provider_in_scope_v1(p_provider uuid) returns boolean
language sql stable security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'ref' as $function$
  with s as (select coalesce((select t.value from pipeline.platform_toolset_settings t where t.toolset_key = 'pipeline' and t.key = 'central.english_provider_types'), '["*"]'::jsonb) v)
  select exists (select 1 from s, jsonb_array_elements_text(case when jsonb_typeof(s.v) = 'array' then s.v else '["*"]'::jsonb end) t
                  where t = '*' or t = (select pt.code from catalogue.providers p join ref.provider_types pt on pt.id = p.provider_type_id where p.id = p_provider))
$function$;
comment on function security.english_provider_in_scope_v1(uuid) is 'CF-247 English requirements (6 Nov 2026 D1): whether the provider''s type is in setting central.english_provider_types (["*"] is every type). Read by the central English route.';

create or replace function security.english_group_match_v1(p_proposal jsonb, p_title text, p_field_path text, p_grp text) returns jsonb
language sql immutable set search_path to 'pg_catalog' as $function$
  -- the course groups of a policy that a person has bound to a course: the group's level fits the course's level group, and the course's field of education sits under one of the
  -- binding's fields (the field itself or any field below it), or its title matches the binding's pattern. Only a binding with a person recorded (bound_by) counts.
  select coalesce(jsonb_agg(jsonb_build_object('group_name', g->>'group_name', 'level', g->>'level', 'reqs', g->'reqs')), '[]'::jsonb)
    from jsonb_array_elements(case when jsonb_typeof(p_proposal->'group_bindings') = 'array' then p_proposal->'group_bindings' else '[]'::jsonb end) b
    join lateral jsonb_array_elements(case when jsonb_typeof(p_proposal->'groups') = 'array' then p_proposal->'groups' else '[]'::jsonb end) g
      on g->>'group_name' = b->>'group_name' and coalesce(g->>'level', '') = coalesce(b->>'level', '')
   where coalesce(b->>'bound_by', '') <> ''
     and jsonb_typeof(g->'reqs') = 'array' and jsonb_array_length(g->'reqs') > 0
     and (coalesce(b->>'level', '') = '' or b->>'level' = p_grp)
     and (exists (select 1 from jsonb_array_elements_text(case when jsonb_typeof(b->'field_paths') = 'array' then b->'field_paths' else '[]'::jsonb end) fp
                   where p_field_path is not null and (p_field_path = fp or left(p_field_path, length(fp) + 1) = fp || '/'))
          or (coalesce(b->>'title_regex', '') <> '' and p_title ~* (b->>'title_regex')))
$function$;
comment on function security.english_group_match_v1(jsonb, text, text, text) is 'CF-247 English requirements (6 Nov 2026 D2): the person-bound course groups of an English policy that apply to a course (level, field of education path, title pattern). Pure; used by provider_english_plan_v1.';

create or replace function public.svc_provider_policy_reparse_next(p_parser text, p_limit integer) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return coalesce((select jsonb_agg(s.x) from (
    select jsonb_build_object('id', f.id, 'provider', p.canonical_name, 'url', f.url, 'storage_path', e.storage_path) x
      from pipeline.provider_fact_sources f
      join pipeline.evidence_artifacts e on e.id = f.evidence_id and e.storage_path is not null
      join catalogue.providers p on p.id = f.provider_id
     where f.kind = 'english_policy' and f.status in ('read', 'parsed', 'no_values')
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = f.provider_id)  -- unpublished providers wait, as for the other policy jobs
       and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.fact_source_id = f.id and pp.parser = p_parser)  -- each page is read once per parser version
       and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.fact_source_id = f.id and pp.status in ('approved', 'proposed'))  -- a live reading is never read over
       and exists (select 1 from pipeline.provider_policy_proposals pp where pp.fact_source_id = f.id
                      and (pp.status = 'no_values' or (pp.status = 'rejected' and coalesce(pp.decision_note, '') ~* 'facult')))
     order by (select count(*) from catalogue.courses c where c.provider_id = f.provider_id and c.lifecycle_status = 'active') desc, f.id
     limit greatest(1, least(coalesce(p_limit, 20), 200))) s), '[]'::jsonb);  -- fixed: per-call safety cap; the run size is batch.policy_reparse
end $function$;
comment on function public.svc_provider_policy_reparse_next(text, integer) is 'CF-247 English requirements (6 Nov 2026 D5): stored English pages whose latest reading gave no values (or was rejected as one faculty row) and that the given parser has not read. The policy-add-tests job reads them again from the stored copy: no Firecrawl, no AI.';
revoke all on function public.svc_provider_policy_reparse_next(text, integer) from public, anon, authenticated;
grant execute on function public.svc_provider_policy_reparse_next(text, integer) to service_role;
revoke all on function security.english_provider_in_scope_v1(uuid), security.english_group_match_v1(jsonb, text, text, text) from public, anon, authenticated;

-- 3 replaced functions (each guarded above on its live md5) --------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.svc_provider_policy_record(p_source_id uuid, p_parsed jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f pipeline.provider_fact_sources%rowtype; v_id uuid; v_status text; v_parser text := coalesce(p_parsed->>'parser', 'unknown');
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into f from pipeline.provider_fact_sources where id = p_source_id;
  if f.id is null or f.kind not in ('english_policy', 'intake_calendar') then raise exception 'not an English policy or calendar document'; end if;
  if jsonb_typeof(p_parsed) <> 'object' then raise exception 'parsed result must be an object'; end if;
  v_status := case
    when f.kind = 'english_policy' and (coalesce(p_parsed->'defaults', '{}'::jsonb) <> '{}'::jsonb
           or exists (select 1 from jsonb_array_elements(coalesce(p_parsed->'exceptions', '[]'::jsonb)) e
                       where jsonb_typeof(e->'reqs') = 'array' and jsonb_array_length(e->'reqs') > 0)
           -- CF-247 6 Nov 2026 (English requirements, parser v0.3.0): a faculty or course-group table is a proposal when a group has a quoted score
           or (jsonb_typeof(p_parsed->'groups') = 'array' and exists (select 1 from jsonb_array_elements(p_parsed->'groups') g, jsonb_array_elements(case when jsonb_typeof(g->'reqs') = 'array' then g->'reqs' else '[]'::jsonb end) q
                where coalesce(q->>'quote', '') <> '' and q->>'overall_score' ~ '^[0-9]+(\.[0-9]+)?$'))) then 'proposed'
    when f.kind = 'intake_calendar' and jsonb_array_length(coalesce(p_parsed->'periods', '[]'::jsonb)) > 0 then 'proposed'
    else 'no_values' end;
  insert into pipeline.provider_policy_proposals(provider_id, fact_source_id, kind, parser, content_hash, evidence_id, url, style, proposal, status)
  values (f.provider_id, f.id, f.kind, v_parser, f.content_hash, f.evidence_id, f.url, left(p_parsed->>'style', 40), p_parsed, v_status)
  on conflict on constraint provider_policy_proposals_key do update
     set proposal = case when pipeline.provider_policy_proposals.proposal ? 'group_bindings' then excluded.proposal || jsonb_build_object('group_bindings', pipeline.provider_policy_proposals.proposal->'group_bindings') else excluded.proposal end,  -- a person's bindings survive a re-read by the same parser
         style = excluded.style, evidence_id = excluded.evidence_id,
         status = case when pipeline.provider_policy_proposals.status in ('proposed', 'no_values') then excluded.status else pipeline.provider_policy_proposals.status end,
         updated_at = now()
  returning id, status into v_id, v_status;
  update pipeline.provider_policy_proposals set status = 'superseded', updated_at = now()
   where fact_source_id = f.id and id <> v_id and status in ('proposed', 'no_values') and parser <> 'written out from the central page';
  return jsonb_build_object('id', v_id, 'status', v_status);
end $function$;

CREATE OR REPLACE FUNCTION security.policy_auto_approve_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_sum jsonb; v_ag int; v_df int; v_ok int := 0; v_refused int := 0;
        v_max numeric := security.pipeline_num_v1('central.max_disagree_pct', 50);
        v_min int := security.pipeline_num_v1('central.min_compare', 10)::int;
        v_note text := 'Automatic: AI reading of the central page, every value quoted on the page (Platform Admin 15 Oct 2026: "Central pages, per course group", "Auto-approve checked AI proposals")';
begin
  if not coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'central.auto_approve'), false) then
    return jsonb_build_object('off', true);
  end if;
  for r in select x.* from pipeline.provider_policy_proposals x
             left join pipeline.enrich_focus_providers f on f.provider_id = x.provider_id
            where x.status = 'proposed' and x.kind in ('english_policy', 'intake_calendar')
              -- CF-247 6 Nov 2026 (English requirements, decision D2): a faculty or course-group reading is never approved automatically; a person approves it and binds its groups
              and (x.kind <> 'english_policy' or jsonb_array_length(case when jsonb_typeof(x.proposal->'groups') = 'array' then x.proposal->'groups' else '[]'::jsonb end) = 0)
              and (x.parser like 'ai:%'
                   -- CF-247 decision 5 Nov 2026 §2: a deterministic dated calendar reading, only when the Platform Admin switches it on
                   or (x.kind = 'intake_calendar' and x.parser = 'provider-policy-calendar-dates-v2' and security.pipeline_num_v1('central.auto_approve_calendar_dates', 0) = 1
                       and security.calendar_scope_v1(x.proposal, x.url, x.parser) = 'main_teaching'))
              -- 23 Oct 2026 (Platform Admin 12:40): English rules for every university, not only the focus list
              and (coalesce(f.in_focus, false)
                   or (x.kind = 'english_policy' and coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'central.auto_approve_english_all'), false)))
            order by f.rank nulls last, x.created_at loop
    if r.kind = 'english_policy' then
      v_sum := security.provider_policy_refresh_one_v1(r.id);
      v_ag := coalesce((v_sum->>'agrees')::int, 0); v_df := coalesce((v_sum->>'differs')::int, 0);
      if v_ag + v_df >= v_min and 100.0 * v_df / (v_ag + v_df) > v_max then
        insert into pipeline.enrichment_flags(entity, entity_key, provider_id, field, reason_code, reason, source)
        values ('policy', r.id::text, r.provider_id, 'english', 'policy_disagrees',
                format('Not approved automatically: %s course pages agree and %s disagree with this default; a person decides (%s)', v_ag, v_df, r.url), 'policy-auto-approve')
        on conflict (entity, entity_key, field, reason_code) do update set reason = excluded.reason, flagged_at = now(), cleared_at = null;
        v_refused := v_refused + 1;
        continue;
      end if;
    end if;
    update pipeline.provider_policy_proposals set status = 'approved', decided_by = null, decided_at = now(), decision_note = v_note, updated_at = now() where id = r.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('policies', 'approve', r.kind || ': ' || r.url, jsonb_build_object('decision', 'Platform Admin 15 Oct 2026: automatic approval of checked AI readings', 'proposal_id', r.id, 'provider_id', r.provider_id), null);
    update pipeline.provider_policy_proposals
       set status = 'superseded', decided_at = now(), updated_at = now(), decision_note = 'Closed: another document for this university was approved (' || r.url || ')'
     where provider_id = r.provider_id and kind = r.kind and status = 'proposed' and id <> r.id
       and (r.kind <> 'intake_calendar' or fact_source_id is not distinct from r.fact_source_id)
       and jsonb_array_length(case when jsonb_typeof(proposal->'groups') = 'array' then proposal->'groups' else '[]'::jsonb end) = 0;  -- CF-247 6 Nov 2026: an automatic approval never closes a course-group reading a person has yet to decide (5 Nov 2026: one calendar document never closes another's)
    v_ok := v_ok + 1;
  end loop;
  return jsonb_build_object('approved', v_ok, 'refused', v_refused);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_provider_policy_decide(p_id uuid, p_action text, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare x pipeline.provider_policy_proposals%rowtype; v jsonb := '{}'::jsonb; v_ag int := 0; v_df int := 0; v_sum jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if p_action not in ('approve', 'reject') then raise exception 'action must be approve or reject'; end if;
  select * into x from pipeline.provider_policy_proposals where id = p_id for update;
  if x.id is null then raise exception 'proposal not found'; end if;
  if x.status <> 'proposed' then raise exception 'already decided or not a proposal (%)', x.status; end if;
  if p_action = 'approve' and x.kind = 'english_policy' then
    v_sum := security.provider_policy_refresh_one_v1(p_id);
    v_ag := coalesce((v_sum->>'agrees')::int, 0); v_df := coalesce((v_sum->>'differs')::int, 0);
    if v_ag + v_df >= 10 and v_df > v_ag then
      raise exception 'This default does not match most course pages (% agree, % differ), so it cannot be approved', v_ag, v_df;
    end if;
  end if;
  update pipeline.provider_policy_proposals set status = case when p_action = 'approve' then 'approved' else 'rejected' end,
         decided_by = auth.uid(), decided_at = now(), decision_note = left(p_note, 500), updated_at = now() where id = p_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('policies', p_action, x.kind || ': ' || x.url, jsonb_build_object('decision', 'Decision 227', 'proposal_id', x.id, 'provider_id', x.provider_id), auth.uid());
  -- one approved document per university and kind: its other waiting documents are closed
  if p_action = 'approve' then
    update pipeline.provider_policy_proposals
       set status = 'superseded', decided_at = now(), updated_at = now(),
           decision_note = 'Closed: another document for this university was approved (' || x.url || ')'
     where provider_id = x.provider_id and kind = x.kind and status = 'proposed' and id <> x.id
       -- CF-247 6 Nov 2026 (English requirements): a course-group reading and a level-default reading are decided separately; approving one never closes the other
       and (jsonb_array_length(case when jsonb_typeof(proposal->'groups') = 'array' then proposal->'groups' else '[]'::jsonb end) > 0) = (jsonb_array_length(case when jsonb_typeof(x.proposal->'groups') = 'array' then x.proposal->'groups' else '[]'::jsonb end) > 0);
  end if;
  if p_action = 'approve' and x.kind = 'english_policy' then v := jsonb_build_object('to_fill', coalesce((v_sum->>'write')::int, 0)); end if;
  if p_action = 'approve' and x.kind = 'intake_calendar' then
    v := jsonb_build_object('to_answer', (select count(*) from security.semester_intake_plan_v1(x.provider_id) r where r.outcome = 'answer'));
  end if;
  return jsonb_build_object('status', case when p_action = 'approve' then 'approved' else 'rejected' end) || v;
end $function$;

CREATE OR REPLACE FUNCTION security.central_pages_attach_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_att int := 0; v_q int := 0; v_re int := 0; v_ns int := 0; v_max int := security.pipeline_num_v1('central.attach_per_kind', 3)::int; r record;
begin
  -- a university with no approved English rule gets its best suggested central English page not yet tried
  insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status)
  select x.provider_id, 'english_policy', x.url, left(x.title, 200), 5, 'search', 'found'
    from (select s.provider_id, e->>'url' url, e->>'title' title,
                 row_number() over (partition by s.provider_id order by (e->>'score')::numeric desc) rn
            from pipeline.provider_central_search s cross join lateral jsonb_array_elements(coalesce(s.found, '[]'::jsonb)) e
           where e->>'kind' = 'english_policy' and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)
             and e->>'url' ~ '^https?://'
             and not exists (select 1 from pipeline.provider_fact_sources f where f.provider_id = s.provider_id and f.kind = 'english_policy' and f.url = e->>'url')) x
   where x.rn = 1
     and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = x.provider_id and pp.kind = 'english_policy' and pp.status in ('approved', 'proposed'))
     and not exists (select 1 from pipeline.provider_fact_sources f where f.provider_id = x.provider_id and f.kind = 'english_policy' and f.status in ('found', 'reading'))
     and (select count(*) from pipeline.provider_fact_sources f where f.provider_id = x.provider_id and f.kind = 'english_policy') < v_max
     and exists (select 1 from catalogue.courses c where c.provider_id = x.provider_id and c.lifecycle_status = 'active')
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = x.provider_id)
     and security.english_provider_in_scope_v1(x.provider_id)  -- CF-247 6 Nov 2026 (decision D1): central.english_provider_types, shipped with today's scope (every type)
  on conflict (provider_id, kind, url) do nothing;
  get diagnostics v_att = row_count;
  -- a university with no approved rule and no suggested central English page left is searched again (job central-find)
  update pipeline.provider_central_search s set state = 'queued', attempts = 0, leased_until = null, updated_at = now()
   where s.provider_id in (
     select s2.provider_id from pipeline.provider_central_search s2
      where s2.state in ('done', 'failed') and s2.updated_at < now() - make_interval(days => security.pipeline_num_v1('central.research_days', 7)::int)
        and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = s2.provider_id and pp.kind = 'english_policy' and pp.status in ('approved', 'proposed'))
        and not exists (select 1 from jsonb_array_elements(coalesce(s2.found, '[]'::jsonb)) e
                         where e->>'kind' = 'english_policy' and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)
                           and not exists (select 1 from pipeline.provider_fact_sources f where f.provider_id = s2.provider_id and f.kind = 'english_policy' and f.url = e->>'url'))
        and not exists (select 1 from pipeline.provider_fact_sources f where f.provider_id = s2.provider_id and f.kind = 'english_policy' and f.status in ('found', 'reading'))
        and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s2.provider_id)
        and security.english_provider_in_scope_v1(s2.provider_id)
        and exists (select 1 from catalogue.courses c where c.provider_id = s2.provider_id and c.lifecycle_status = 'active')
      order by (select count(*) from catalogue.courses c2 where c2.provider_id = s2.provider_id and c2.lifecycle_status = 'active') desc
      limit greatest(0, security.pipeline_num_v1('central.research_per_run', 30)::int - (select count(*) from pipeline.provider_central_search q where q.state in ('queued', 'leased'))::int));
  get diagnostics v_re = row_count;
  -- CF-247 6 Nov 2026 (decision D3): the search for providers that have no central English page yet is built and SWITCHED OFF (central.english_search_non_university = 0).
  -- When a person switches it on, up to batch.english_search_non_university providers a run are queued for the existing provider-facts job, which searches inside the
  -- provider's own website and the Firecrawl daily share for central pages. Nothing is queued while the switch is 0.
  if security.pipeline_num_v1('central.english_search_non_university', 0) = 1 then
    insert into pipeline.provider_fact_search(provider_id, kind)
    select p.id, 'english_policy'
      from catalogue.providers p left join ref.provider_types pt on pt.id = p.provider_type_id
     where coalesce(pt.code, '') <> 'university' and coalesce(btrim(p.website), '') ~* '^https?://'
       and security.english_provider_in_scope_v1(p.id)
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
       and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
       and not exists (select 1 from pipeline.provider_fact_search fs where fs.provider_id = p.id and fs.kind = 'english_policy')
       and not exists (select 1 from pipeline.provider_fact_sources f where f.provider_id = p.id and f.kind = 'english_policy')
       and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = p.id and pp.kind = 'english_policy' and pp.status in ('approved', 'proposed'))
     order by (select count(*) from catalogue.courses c2 where c2.provider_id = p.id and c2.lifecycle_status = 'active') desc, p.id
     limit security.pipeline_num_v1('batch.english_search_non_university', 10)::int
    on conflict (provider_id, kind) do nothing;
    get diagnostics v_ns = row_count;
  end if;
  -- read central English pages go to the pinned AI (the database checks each quote; policy-auto-approve decides)
  for r in select distinct f.provider_id from pipeline.provider_fact_sources f
            where f.kind = 'english_policy' and f.status in ('read', 'parsed', 'no_values')
              and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = f.provider_id and pp.kind = 'english_policy' and pp.status = 'approved') loop
    v_q := v_q + security.central_ai_enqueue_v1(r.provider_id);
  end loop;
  return jsonb_build_object('attached', v_att, 'searched_again', v_re, 'queued_for_ai', v_q, 'search_queued', v_ns);
end $function$;

CREATE OR REPLACE FUNCTION security.central_ai_enqueue_v1(p_provider uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int;
begin
  if not coalesce((select s.enabled from pipeline.central_ai_settings s where s.id = 1), false) then return 0; end if;
  insert into pipeline.central_ai_queue(fact_source_id, provider_id, kind, content_hash)
  select f.id, f.provider_id, f.kind, f.content_hash from pipeline.provider_fact_sources f
    join pipeline.evidence_artifacts e on e.id = f.evidence_id and e.storage_path is not null
   where f.provider_id = p_provider and f.kind in ('english_policy', 'intake_calendar') and f.status in ('read', 'parsed', 'no_values')
     and (f.kind <> 'english_policy' or security.english_provider_in_scope_v1(f.provider_id))  -- CF-247 6 Nov 2026 (decision D1): English pages only for the provider types in scope
     and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.fact_source_id = f.id and pp.status in ('proposed', 'approved'))
     and not exists (select 1 from pipeline.central_ai_queue q where q.fact_source_id = f.id and (q.state in ('queued', 'leased') or q.content_hash is not distinct from f.content_hash))
  on conflict do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $function$;

CREATE OR REPLACE FUNCTION security.provider_english_plan_v1(p_proposal_id uuid)
 RETURNS TABLE(course_id uuid, title text, study_level text, plan text, reason text, requirements jsonb, existing jsonb, outcome text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'ref', 'security'
AS $function$
declare x pipeline.provider_policy_proposals%rowtype; v_named jsonb; v_defaults jsonb;
begin
  select * into x from pipeline.provider_policy_proposals where id = p_proposal_id;
  if x.id is null or x.kind <> 'english_policy' then raise exception 'not an English policy proposal'; end if;
  v_defaults := coalesce(x.proposal->'defaults', '{}'::jsonb);
  select coalesce(jsonb_agg(jsonb_build_object('k', s.k, 'reqs', s.reqs)), '[]'::jsonb) into v_named from (
    select security.english_title_key(n) k, null::jsonb reqs from jsonb_array_elements_text(coalesce(x.proposal->'named', '[]'::jsonb)) n
    union all
    select security.english_title_key(e->>'name'), case when jsonb_typeof(e->'reqs') = 'array' and jsonb_array_length(e->'reqs') > 0
                                                       then (select jsonb_agg(q - 'quote') from jsonb_array_elements(e->'reqs') q) end
      from jsonb_array_elements(coalesce(x.proposal->'exceptions', '[]'::jsonb)) e) s where length(s.k) >= 4;
  return query
  with named as materialized (
    select e->>'k' k, nullif(e->'reqs', 'null'::jsonb) reqs,
           array(select distinct t from unnest(regexp_split_to_array(e->>'k', '[ /]+')) t where t not in ('of', 'and', 'in', 'the', '')) toks
      from jsonb_array_elements(v_named) e),
  c0 as materialized (
    select co.id, co.canonical_title t, security.english_title_key(co.canonical_title) k, sl.code lvl, ff.path field_path
      from catalogue.courses co left join ref.study_levels sl on sl.id = co.study_level_id left join ref.fields_of_study ff on ff.id = co.primary_field_id
     where co.provider_id = x.provider_id and co.lifecycle_status = 'active'),
  c as materialized (
    select c0.*, array(select distinct t from unnest(regexp_split_to_array(c0.k, '[ /]+')) t where t not in ('of', 'and', 'in', 'the', '')) toks,
           case when c0.lvl in ('bachelor', 'bachelor_honours', 'associate_degree') then 'undergraduate'
                when c0.lvl in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate'
                when c0.lvl in ('doctorate', 'masters_research') then 'research' end grp,  -- CF-247 15 Oct: research degrees take the policy's research default
           (select coalesce(jsonb_object_agg(et.code, r.overall_score), '{}'::jsonb) from catalogue.course_english_requirements r
              join ref.english_tests et on et.id = r.english_test_id where r.course_id = c0.id and r.status = 'active') ex,
           exists (select 1 from catalogue.course_english_requirements r where r.course_id = c0.id) any_row,
           exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c0.id and l.field in ('english', 'english_requirements', 'course_english')) locked,
           exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = c0.id and i.field_code = 'course_english' and i.status = 'pending') in_review,
           false in_l3,  -- CF-247 15 Oct 2026 (usage audit D6): Layer 3 is retired, so no course waits for it
           exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c0.id and g.status in ('bound', 'ambiguous')
                      and (g.read_status is null or g.read_status = 'needs_render')) page_waiting
      from c0),
  m as (
    select c.*,
           (select jsonb_agg(distinct named.reqs) from named where named.k = c.k and named.reqs is not null) exact_reqs,
           exists (select 1 from named where named.k = c.k) exact_named,
           exists (select 1 from named where named.k <> c.k and (position(named.k in c.k) > 0 or position(c.k in named.k) > 0
                     or (cardinality(c.toks) > 0 and cardinality(named.toks) > 0
                         and (select count(*) from unnest(c.toks) t where t = any(named.toks))::numeric / greatest(cardinality(c.toks), cardinality(named.toks)) >= 0.75))) close_named,
           case when c.grp is not null then v_defaults->c.grp end dflt,
           -- CF-247 6 Nov 2026: the course groups of this policy that a person has bound to this course (undergraduate and postgraduate courses only)
           case when c.grp in ('undergraduate', 'postgraduate') then security.english_group_match_v1(x.proposal, c.t, c.field_path, c.grp) else '[]'::jsonb end grp_hits
      from c),
  m2 as (
    select m.*, g.n grp_n, g.name grp_name,
           -- another approved policy of this provider names this course with its own scores: that is more specific than a group
           (g.n = 1 and exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = x.provider_id and o.kind = 'english_policy' and o.status = 'approved' and o.id <> x.id
              and exists (select 1 from jsonb_array_elements(coalesce(o.proposal->'exceptions', '[]'::jsonb)) e where jsonb_typeof(e->'reqs') = 'array' and jsonb_array_length(e->'reqs') > 0 and security.english_title_key(e->>'name') = m.k))) named_elsewhere,
           -- another approved policy of this provider has a bound course group for this course: it takes the course, so this policy's level default does not
           (m.grp in ('undergraduate', 'postgraduate') and exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = x.provider_id and o.kind = 'english_policy' and o.status = 'approved' and o.id <> x.id
              and jsonb_array_length(security.english_group_match_v1(o.proposal, m.t, m.field_path, m.grp)) > 0)) other_group
      from m cross join lateral (select count(distinct h->'reqs')::int n, min(h->>'group_name') name from jsonb_array_elements(m.grp_hits) h) g),
  p as (
    select m.*,
           case when m.lvl is null then 'held|study level unknown'
                when m.lvl in ('doctorate', 'masters_research') and jsonb_typeof(v_defaults->'research') is distinct from 'array' then 'held|research degree (the policy states no research requirement)'
                when m.t ~* 'exit award' then 'held|exit award only'
                when (m.k ~ '/' or m.k ~ ' and (bachelor|master|doctor|graduate|diploma|associate) (of|in) ') and not security.double_degree_same_group_v1(m.t, m.grp) then 'held|double degree (its parts are at different levels)'
                when m.exact_reqs is not null and jsonb_array_length(m.exact_reqs) > 1 then 'held|the policy gives this course more than one requirement'
                when m.exact_reqs is not null then 'named|'
                when m.exact_named or m.close_named then 'held|named in the policy (it may have its own requirement)'
                when m.grp_n > 1 then 'held|more than one course group applies to this course'
                when m.grp_n = 1 and m.named_elsewhere then 'held|another approved policy of this university names this course'
                when m.grp_n = 1 then 'group|course group: ' || m.grp_name
                when m.grp is null then 'held|level not covered by the policy default'
                when m.dflt is null or jsonb_typeof(m.dflt) <> 'array' then 'held|the policy gives no default for this level'
                when m.other_group then 'held|a course group of another approved policy of this university applies'
                else 'default|' end pr
      from m2 m),
  q as (
    select p.*, split_part(p.pr, '|', 1) pl, nullif(split_part(p.pr, '|', 2), '') rs,
           case when p.pr like 'named|%' then p.exact_reqs->0 when p.pr like 'default|%' then p.dflt
                when p.pr like 'group|%' then (select jsonb_agg(r - 'quote') from jsonb_array_elements(p.grp_hits->0->'reqs') r) end reqs
      from p)
  select q.id, q.t, q.lvl, q.pl, q.rs, q.reqs, q.ex,
         case when q.pl = 'held' then 'held'
              when q.any_row and exists (select 1 from jsonb_array_elements(q.reqs) r where q.ex ? (r->>'test_code') and (q.ex->>(r->>'test_code'))::numeric <> (r->>'overall_score')::numeric) then 'differs'
              when q.any_row and exists (select 1 from jsonb_array_elements(q.reqs) r where q.ex ? (r->>'test_code')) then 'agrees'
              when q.any_row then 'other_value'
              when q.locked then 'set_by_hand'
              when q.in_review then 'in_review'
              when q.in_l3 or q.page_waiting then 'waiting'
              else 'write' end
    from q;
end $function$;

CREATE OR REPLACE FUNCTION security.provider_english_apply_v1(p_proposal_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security', 'search'
AS $function$
declare x pipeline.provider_policy_proposals%rowtype; v_src uuid; v_name text; r record; v_ok int := 0; v_err int := 0; v_courses uuid[] := '{}'; v_last text;
  v_flag boolean; v_flagged int := 0; v_appr text;
begin
  select * into x from pipeline.provider_policy_proposals where id = p_proposal_id;
  if x.id is null or x.kind <> 'english_policy' then raise exception 'not an English policy proposal'; end if;
  if x.status <> 'approved' then raise exception 'proposal is not approved'; end if;
  if x.evidence_id is null then
    select fs.evidence_id into x.evidence_id from pipeline.provider_fact_sources fs where fs.id = x.fact_source_id and fs.url = x.url and fs.evidence_id is not null;
  end if;
  if x.evidence_id is null or coalesce(x.content_hash, '') = '' then raise exception 'the policy document has no stored evidence'; end if;
  v_src := security.coverage_sweep_source(x.provider_id);
  select coalesce(p.display_name, p.canonical_name) into v_name from catalogue.providers p where p.id = x.provider_id;
  v_flag := security.provider_english_flagged(x.proposal);
  -- CF-247 15 Oct: say who approved it
  v_appr := case when x.decided_by is null and coalesce(x.decision_note, '') like 'Automatic:%' then '(approved automatically: every value is quoted on the page; Platform Admin decision 15 Oct 2026)' else '(approved by a Platform Admin, Decision 227)' end;
  -- courses open to international students first
  for r in select pl.* from security.provider_english_plan_v1(p_proposal_id) pl join catalogue.courses co on co.id = pl.course_id
            where pl.outcome = 'write' order by co.open_to_international desc nulls last, pl.title loop
    begin
      perform security.coverage_apply_course_v1(r.course_id, v_src, x.evidence_id, x.url, x.content_hash,
        jsonb_build_object('english_requirements', (select jsonb_agg(jsonb_build_object(
            'test_code', q->>'test_code', 'overall_score', q->'overall_score', 'component_scores', coalesce(q->'component_scores', '{}'::jsonb),
            'source_requirement_key', 'policy:' || x.id || ':' || lower(q->>'test_code'),
            'notes', case when r.plan = 'named' then 'From ' || v_name || '''s English language policy, which names this course ' || v_appr
                          when r.plan = 'group' then 'English requirement for the course group "' || regexp_replace(r.reason, '^course group: ', '') || '" in ' || v_name || '''s English language policy, bound to this course by a Platform Admin ' || v_appr
                          else 'Default for ' || case when r.study_level in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate coursework' when r.study_level in ('doctorate', 'masters_research') then 'research' else 'undergraduate' end
                               || ' courses in ' || v_name || '''s English language policy ' || v_appr
                               || case when v_flag then '. Flagged: this is the university standard; the policy says some courses need more and does not list them, so check the course page' else '' end end))
          from jsonb_array_elements(r.requirements) q where q->>'test_code' in (select code from ref.english_tests))));
      if v_flag and r.plan = 'default' then
        update catalogue.course_english_requirements set confidence = 0.6
         where course_id = r.course_id and source_requirement_key like 'policy:' || x.id || ':%';
        v_flagged := v_flagged + 1;
      end if;
      v_ok := v_ok + 1; v_courses := v_courses || r.course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if v_ok > 0 then
    insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
    select 'courses', 'course_english', v_src, 'approved', 'CF-CHG-20260915-247; Decision 227 (English from the provider''s policy, approved by a Platform Admin)', now(), now(), now()
     where not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'course_english' and g.source_id = v_src);
    perform search.refresh_course_enrichment_scoped_v1(v_courses, true);
  end if;
  update pipeline.provider_policy_proposals
     set apply_summary = coalesce(apply_summary, '{}'::jsonb) || jsonb_build_object('written', coalesce((apply_summary->>'written')::int, 0) + v_ok,
           'refused', v_err, 'last_error', v_last, 'last_applied_at', now(),
           'flagged', coalesce((apply_summary->>'flagged')::int, 0) + v_flagged), updated_at = now()
   where id = p_proposal_id;
  return jsonb_build_object('written', v_ok, 'refused', v_err, 'last_error', v_last);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_provider_policies_read(p_kind text DEFAULT 'english_policy'::text, p_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
  if p_kind not in ('english_policy', 'intake_calendar') then raise exception 'kind must be english_policy or intake_calendar'; end if;
  if p_id is not null then
    select jsonb_build_object('proposal', to_jsonb(x) - 'content_hash', 'provider', coalesce(p.display_name, p.canonical_name),
             'rows', case when x.kind = 'english_policy' then (select coalesce(jsonb_agg(jsonb_build_object('course_id', r.course_id, 'title', r.title, 'study_level', r.study_level,
                   'plan', r.plan, 'reason', r.reason, 'outcome', r.outcome, 'existing', r.existing,
                   'ielts', (select q->'overall_score' from jsonb_array_elements(r.requirements) q where q->>'test_code' = 'IELTS' limit 1))
                   order by case r.outcome when 'write' then 0 when 'differs' then 1 when 'agrees' then 2 else 3 end, r.title), '[]'::jsonb)
                   from security.provider_english_plan_v1(x.id) r) end)
      into v from pipeline.provider_policy_proposals x join catalogue.providers p on p.id = x.provider_id
     where x.id = p_id and x.kind = p_kind;
    if v is null then raise exception 'proposal not found'; end if;
    return v;
  end if;
  select jsonb_build_object(
    'can_decide', security.current_role_rank() >= 6,
    'totals', jsonb_build_object(
      'documents_found', (select count(*) from pipeline.provider_fact_sources f where f.kind = p_kind),
      'documents_read', (select count(*) from pipeline.provider_fact_sources f where f.kind = p_kind and f.status in ('read', 'parsed', 'no_values')),
      'providers_found', (select count(distinct f.provider_id) from pipeline.provider_fact_sources f where f.kind = p_kind),
      'no_values_by_style', (select coalesce(jsonb_object_agg(coalesce(style, 'none'), n), '{}'::jsonb) from (select style, count(*) n from pipeline.provider_policy_proposals
                               where kind = p_kind and status = 'no_values' group by 1) s)),
    'proposals', (select coalesce(jsonb_agg(jsonb_build_object(
         'id', x.id, 'provider_id', x.provider_id, 'provider', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2,
         'url', x.url, 'style', x.style, 'status', x.status, 'parser', x.parser, 'created_at', x.created_at,
         'decided_at', x.decided_at, 'decision_note', x.decision_note, 'apply_summary', x.apply_summary,
         'caveats', x.proposal->'caveats', 'conflicts', x.proposal->'conflicts',
         'defaults', x.proposal->'defaults', 'periods', x.proposal->'periods',
         'group_count', jsonb_array_length(case when jsonb_typeof(x.proposal->'groups') = 'array' then x.proposal->'groups' else '[]'::jsonb end), 'bound_groups', jsonb_array_length(coalesce(x.proposal->'group_bindings', '[]'::jsonb)),
         'named_requirements', (select count(*) from jsonb_array_elements(coalesce(x.proposal->'exceptions', '[]'::jsonb)) e where jsonb_typeof(e->'reqs') = 'array' and jsonb_array_length(e->'reqs') > 0),
         'named_courses', jsonb_array_length(coalesce(x.proposal->'named', '[]'::jsonb)),
         'plan', x.plan_summary, 'plan_at', x.plan_at)
       order by (x.status = 'proposed') desc, coalesce(p.display_name, p.canonical_name)), '[]'::jsonb)
       from pipeline.provider_policy_proposals x join catalogue.providers p on p.id = x.provider_id left join ref.countries k on k.id = p.country_id
      where x.kind = p_kind and x.status in ('proposed', 'approved', 'rejected'))) into v;
  return v;
end $function$;

CREATE OR REPLACE FUNCTION public.svc_provider_facts_search_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with pick as (
    select s.provider_id, s.kind, dom.d search_domain
      from pipeline.provider_fact_search s
      join catalogue.providers pr on pr.id = s.provider_id
      left join pipeline.course_link_recipes r on r.provider_id = s.provider_id and r.active
      -- CF-247 6 Nov 2026 (English requirements, decision D3): without a course link recipe, a provider's own website host is the search domain for its English
      -- page, and only while central.english_search_non_university is 1 (shipped 0, so the picks are exactly what they were)
      cross join lateral (select coalesce(r.search_domain, case when s.kind = 'english_policy' and security.pipeline_num_v1('central.english_search_non_university', 0) = 1
                                  then nullif(regexp_replace(regexp_replace(coalesce(btrim(pr.website), ''), '^https?://(www\.)?', '', 'i'), '[/?#].*$', ''), '') end) d) dom
     where dom.d is not null
       and (s.state = 'queued' or (s.state = 'sent' and s.sent_at < now() - interval '20 minutes' and s.attempts < security.pipeline_num_v1('retry.provider_facts_attempts', 3)))
       and (s.kind <> 'fee_schedule' or security.tuition_chase_enabled(s.provider_id))
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = s.provider_id)  -- v2.15.237: paused while the provider is unpublished or archived
     order by (s.kind <> 'fee_schedule'), s.queued_at, s.provider_id limit greatest(1, least(coalesce(p_limit, 20), 60))
     for update of s skip locked),
  upd as (
    update pipeline.provider_fact_search s set state = 'sent', sent_at = now(), attempts = s.attempts + 1,
           query = case p.kind when 'fee_schedule' then 'international student tuition fees site:' || p.search_domain
                               when 'english_policy' then 'English language requirements international students site:' || p.search_domain
                               else 'academic calendar key dates intakes site:' || p.search_domain end
      from pick p where s.provider_id = p.provider_id and s.kind = p.kind
    returning s.provider_id, s.kind, s.query)
  select coalesce(jsonb_agg(jsonb_build_object('provider_id', provider_id, 'kind', kind, 'query', query)), '[]'::jsonb) into v from upd;
  return v;
end $function$;

-- 4 binding groups to courses (a Platform Admin, logged) -----------------------------------------------------------------------------------------------------
create or replace function public.admin_provider_english_groups_set_v1(p_proposal_id uuid, p_bindings jsonb, p_reason text) returns jsonb
language plpgsql security definer set search_path to '' as $function$
declare x pipeline.provider_policy_proposals%rowtype; b jsonb; g jsonb; v_out jsonb := '[]'::jsonb; v_fields text[]; v_paths text[]; v_code text; v_path text;
        v_reason text := btrim(coalesce(p_reason, '')); v_regex text; v_withdrawn int := 0; v_ids uuid[]; v_plan jsonb; v_day text := to_char(now() at time zone 'Australia/Melbourne', 'FMDD Mon YYYY');
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  select * into x from pipeline.provider_policy_proposals where id = p_proposal_id for update;
  if x.id is null or x.kind <> 'english_policy' then raise exception 'not an English policy proposal'; end if;
  if x.status not in ('proposed', 'approved') then raise exception 'a % policy cannot be bound', x.status; end if;
  if jsonb_typeof(x.proposal->'groups') is distinct from 'array' or jsonb_array_length(x.proposal->'groups') = 0 then raise exception 'this policy has no course groups'; end if;
  if jsonb_typeof(p_bindings) is distinct from 'array' then raise exception 'bindings must be a list'; end if;
  for b in select e from jsonb_array_elements(p_bindings) e loop
    g := null;
    select gg into g from jsonb_array_elements(x.proposal->'groups') gg where gg->>'group_name' = b->>'group_name' and coalesce(gg->>'level', '') = coalesce(b->>'level', '') limit 1;
    if g is null then raise exception 'course group "%" (level %) is not in this policy', b->>'group_name', coalesce(b->>'level', 'any'); end if;
    v_fields := array(select distinct btrim(f) from jsonb_array_elements_text(case when jsonb_typeof(b->'fields') = 'array' then b->'fields' else '[]'::jsonb end) f where btrim(f) <> '');
    v_paths := '{}';
    foreach v_code in array v_fields loop
      v_path := null;
      select path into v_path from ref.fields_of_study where code = v_code and status = 'active';
      if v_path is null then raise exception 'field of education "%" is not an active field', v_code; end if;
      v_paths := v_paths || v_path;
    end loop;
    v_regex := nullif(btrim(coalesce(b->>'title_regex', '')), '');
    if v_regex is not null then
      if length(v_regex) > 200 then raise exception 'the title pattern is too long'; end if;  -- fixed: a bound on a person's pattern, not an operational value
      begin perform '' ~* v_regex; exception when others then raise exception 'the title pattern is not a valid pattern'; end;
    end if;
    if cardinality(v_fields) = 0 and v_regex is null then raise exception 'course group "%" needs at least one field of education or a title pattern', b->>'group_name'; end if;
    v_out := v_out || jsonb_build_object('group_name', g->>'group_name', 'level', g->'level', 'fields', to_jsonb(v_fields), 'field_paths', to_jsonb(v_paths), 'title_regex', v_regex,
                                         'note', left(coalesce(b->>'note', ''), 300), 'bound_by', auth.uid(), 'bound_at', now());
  end loop;
  update pipeline.provider_policy_proposals set proposal = jsonb_set(proposal, '{group_bindings}', v_out, true), updated_at = now() where id = x.id;
  -- rows an earlier binding wrote for a course the bindings no longer reach are withdrawn (kept, not deleted)
  with w as (
    update catalogue.course_english_requirements e set status = 'withdrawn', last_verified_at = now(),
           notes = coalesce(e.notes, '') || format(' Withdrawn %s: the course group binding of this policy changed and no longer reaches this course.', v_day)
     where e.status = 'active' and e.source_requirement_key like 'policy:' || x.id || ':%' and e.notes like 'English requirement for the course group%'
       and e.course_id not in (select pl.course_id from security.provider_english_plan_v1(x.id) pl where pl.plan = 'group')
    returning e.course_id)
  select coalesce(array_agg(course_id), '{}'), count(*) into v_ids, v_withdrawn from w;
  if v_withdrawn > 0 then perform search.refresh_course_enrichment_scoped_v1(v_ids, true); end if;
  v_plan := security.provider_policy_refresh_one_v1(x.id);
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('policies', 'english_groups_bound', 'english_policy: ' || x.url,
          jsonb_build_object('decision', 'Platform Admin 6 Nov 2026 §3 D2', 'proposal_id', x.id, 'provider_id', x.provider_id, 'bindings', v_out, 'reason', v_reason, 'withdrawn_rows', v_withdrawn), auth.uid());
  return jsonb_build_object('bound', jsonb_array_length(v_out), 'withdrawn_rows', v_withdrawn, 'plan', v_plan);
end $function$;
comment on function public.admin_provider_english_groups_set_v1(uuid, jsonb, text) is 'CF-247 English requirements (6 Nov 2026 D2): a Platform Admin binds the course groups of an English policy (faculty or course-group table) to courses by ASCED field of education and/or a title pattern, with a reason. Only a bound group reaches a course, and only once the policy is approved. Logged in admin_control_events.';
revoke all on function public.admin_provider_english_groups_set_v1(uuid, jsonb, text) from public, anon;
grant execute on function public.admin_provider_english_groups_set_v1(uuid, jsonb, text) to authenticated, service_role;

-- 5 why there is no rule: one row per provider, from persisted records only (existing English policies panel) --------------------------------------------
create or replace function security.english_policy_status_v1(p_provider uuid default null, p_stage text default null, p_limit integer default 200)
returns table(provider_id uuid, provider text, country text, provider_type text, active_courses bigint, missing_courses bigint, in_scope boolean, stage text, why text,
              pages_tried jsonb, last_reading jsonb, group_count integer, bound_groups integer, next_try text)
language sql stable security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'ref', 'security' as $function$
  with base as (
    select p.id, coalesce(p.display_name, p.canonical_name) nm, k.iso_alpha2 cc, pt.code ptc, count(c.id) ac,
           count(c.id) filter (where not exists (select 1 from catalogue.course_english_requirements r where r.course_id = c.id and r.status = 'active')) mc
      from catalogue.providers p
      join catalogue.courses c on c.provider_id = p.id and c.lifecycle_status = 'active'
      left join ref.countries k on k.id = p.country_id
      left join ref.provider_types pt on pt.id = p.provider_type_id
     where (p_provider is null or p.id = p_provider) and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
     group by p.id, p.display_name, p.canonical_name, k.iso_alpha2, pt.code),
  f as (
    select b.*,
      (select count(*) from pipeline.provider_policy_proposals pp where pp.provider_id = b.id and pp.kind = 'english_policy' and pp.status = 'approved') ap,
      (select count(*) from pipeline.provider_policy_proposals pp where pp.provider_id = b.id and pp.kind = 'english_policy' and pp.status = 'proposed') pr,
      (select count(*) from pipeline.provider_policy_proposals pp where pp.provider_id = b.id and pp.kind = 'english_policy' and pp.status in ('proposed', 'approved')
          and jsonb_array_length(case when jsonb_typeof(pp.proposal->'groups') = 'array' then pp.proposal->'groups' else '[]'::jsonb end) > 0) pg,
      (select count(*) from pipeline.provider_policy_proposals pp where pp.provider_id = b.id and pp.kind = 'english_policy' and pp.status = 'rejected') rj,
      (select coalesce(sum(jsonb_array_length(case when jsonb_typeof(pp.proposal->'groups') = 'array' then pp.proposal->'groups' else '[]'::jsonb end)), 0) from pipeline.provider_policy_proposals pp
         where pp.provider_id = b.id and pp.kind = 'english_policy' and pp.status in ('proposed', 'approved'))::int gc,
      (select coalesce(sum(jsonb_array_length(case when jsonb_typeof(pp.proposal->'group_bindings') = 'array' then pp.proposal->'group_bindings' else '[]'::jsonb end)), 0) from pipeline.provider_policy_proposals pp
         where pp.provider_id = b.id and pp.kind = 'english_policy' and pp.status in ('proposed', 'approved'))::int bg,
      (select count(*) from pipeline.provider_fact_sources fs where fs.provider_id = b.id and fs.kind = 'english_policy') srcs,
      (select count(*) from pipeline.provider_fact_sources fs where fs.provider_id = b.id and fs.kind = 'english_policy' and fs.status in ('read', 'parsed', 'no_values') and fs.evidence_id is not null) stored,
      cs.state cstate, cs.updated_at cat,
      (select count(*) from jsonb_array_elements(coalesce(cs.found, '[]'::jsonb)) e where e->>'kind' = 'english_policy') cands,
      (select count(*) from jsonb_array_elements(coalesce(cs.found, '[]'::jsonb)) e where e->>'kind' = 'english_policy'
          and coalesce((e->>'score')::numeric, 0) >= security.pipeline_num_v1('central.min_suggest_score', 4)) strong
      from base b left join pipeline.provider_central_search cs on cs.provider_id = b.id),
  s as (
    select f.*, case when f.ap > 0 then 'approved' when f.pg > 0 then 'group_proposed' when f.pr > 0 then 'rule_proposed' when f.rj > 0 then 'rejected'
                     when f.stored > 0 then 'page_read_no_rule' when f.srcs > 0 then 'page_not_stored' when f.cands > 0 and f.strong = 0 then 'weak_candidates_only'
                     when f.cstate = 'done' then 'mapped_no_page' else 'not_mapped' end st from f)
  select s.id, s.nm, s.cc, s.ptc, s.ac, s.mc, security.english_provider_in_scope_v1(s.id), s.st,
         case when not security.english_provider_in_scope_v1(s.id) and s.st not in ('approved', 'group_proposed', 'rule_proposed') then 'Not searched: this provider type is outside central.english_provider_types'
              when s.st = 'approved' then 'An approved English policy covers this provider; ' || s.mc || ' of its courses still have no English requirement (levels or groups the policy does not cover, courses it names, research and double degrees stay held)'
              when s.st = 'group_proposed' then 'A faculty or course-group table was read: waiting for a Platform Admin to approve it and bind each group to courses'
              when s.st = 'rule_proposed' then 'A policy reading is waiting for approval'
              when s.st = 'rejected' then 'The last reading was rejected: ' || coalesce((select left(pp.decision_note, 160) from pipeline.provider_policy_proposals pp where pp.provider_id = s.id and pp.kind = 'english_policy' and pp.status = 'rejected' order by pp.decided_at desc nulls last limit 1), 'no reason recorded')
              when s.st = 'page_read_no_rule' then 'A page was read and gave no usable values (' || coalesce((select pp.style from pipeline.provider_policy_proposals pp where pp.provider_id = s.id and pp.kind = 'english_policy' order by pp.created_at desc limit 1), 'no reading recorded') || '); it is read again from the stored copy when the policy parser changes'
              when s.st = 'page_not_stored' then 'A page was found but its copy is not stored yet'
              when s.st = 'weak_candidates_only' then 'Only weak candidate pages were found (below the minimum score of ' || security.pipeline_num_v1('central.min_suggest_score', 4) || ')'
              when s.st = 'mapped_no_page' then 'Site mapped on ' || to_char(s.cat at time zone 'Australia/Melbourne', 'FMDD Mon YYYY') || '; no English page was found'
              else 'Site not mapped yet' end,
         coalesce((select jsonb_agg(jsonb_build_object('url', fs.url, 'status', fs.status, 'attempts', fs.attempts, 'found_via', fs.found_via, 'read_at', fs.read_at) order by fs.rank, fs.created_at) from pipeline.provider_fact_sources fs where fs.provider_id = s.id and fs.kind = 'english_policy'), '[]'::jsonb),
         (select jsonb_build_object('parser', pp.parser, 'status', pp.status, 'style', pp.style, 'at', pp.created_at, 'note', left(pp.decision_note, 200)) from pipeline.provider_policy_proposals pp
           where pp.provider_id = s.id and pp.kind = 'english_policy' order by pp.created_at desc limit 1),
         s.gc, s.bg,
         case when s.st in ('group_proposed', 'rule_proposed') then 'needs a person'
              when s.st in ('mapped_no_page', 'not_mapped', 'weak_candidates_only') then
                case when s.cat is null then 'at the next central-find run' else to_char((s.cat + make_interval(days => security.pipeline_num_v1('central.research_days', 7)::int)) at time zone 'Australia/Melbourne', 'FMDD Mon YYYY') end
              when s.st = 'page_read_no_rule' then 'at the next policy-add-tests run after the parser changes'
              when s.st = 'approved' then 'when its pages change' else 'at the next central-attach run' end
    from s where (p_stage is null or s.st = p_stage)
   order by s.mc desc, s.nm limit greatest(1, least(coalesce(p_limit, 200), 1000));  -- fixed: display cap for one panel read
$function$;
comment on function security.english_policy_status_v1(uuid, text, integer) is 'CF-247 English requirements (6 Nov 2026 §5): one row per published provider with active courses: stage on the English policy route, pages tried, last reading, why there is no rule, group counts and the next try. Persisted records only.';
revoke all on function security.english_policy_status_v1(uuid, text, integer) from public, anon, authenticated;

create or replace function public.admin_provider_english_status_read(p_provider uuid default null, p_stage text default null, p_limit integer default 200) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
declare v jsonb;
begin
  if auth.uid() is null or security.current_role_rank() < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
  select jsonb_build_object(
    'stages', (select coalesce(jsonb_object_agg(a.stage, jsonb_build_object('providers', a.n, 'missing_courses', a.m)), '{}'::jsonb)
                 from (select s.stage, count(*) n, sum(s.missing_courses) m from security.english_policy_status_v1(p_provider, null, 1000) s group by 1) a),
    'rows', (select coalesce(jsonb_agg(to_jsonb(s)), '[]'::jsonb) from security.english_policy_status_v1(p_provider, p_stage, p_limit) s),
    'proposals', (select coalesce(jsonb_object_agg(a.status, a.n), '{}'::jsonb) from (select pp.status, count(*) n from pipeline.provider_policy_proposals pp where pp.kind = 'english_policy' group by 1) a),
    'rows_from_groups', (select count(*) from catalogue.course_english_requirements e where e.status = 'active' and e.notes like 'English requirement for the course group%'),
    'credits_7d', (select coalesce(jsonb_object_agg(a.purpose, a.u), '{}'::jsonb) from (select u.purpose, sum(u.units) u from pipeline.coverage_vendor_usage u
                    where u.purpose in ('central_map', 'provider_facts_search', 'provider_facts_scrape') and u.at > now() - interval '7 days' group by 1) a),
    'scope', jsonb_build_object('provider_types', coalesce((select t.value from pipeline.platform_toolset_settings t where t.toolset_key = 'pipeline' and t.key = 'central.english_provider_types'), '["*"]'::jsonb),
                                'search_new_providers', security.pipeline_num_v1('central.english_search_non_university', 0)),
    'jobs', (select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'schedule', j.schedule, 'active', j.active,
                  'last_run', (select jsonb_build_object('at', d.start_time, 'status', d.status) from cron.job_run_details d where d.jobid = j.jobid order by d.start_time desc limit 1)) order by j.jobname), '[]'::jsonb)
               from cron.job j where j.jobname in ('central-find', 'central-attach', 'central-ai', 'provider-facts', 'policy-auto-approve', 'provider-english-defaults', 'policy-add-tests', 'coverage-admit')))
    into v;
  return v;
end $function$;
comment on function public.admin_provider_english_status_read(uuid, text, integer) is 'CF-247 English requirements (6 Nov 2026 §5): Coverage › Attributes › English policies, "No rule yet": providers by stage with the reason and the next try, the proposals by status, rows written from course groups, central credits used in 7 days, the provider-type scope, and the jobs of the route. Read only.';
revoke all on function public.admin_provider_english_status_read(uuid, text, integer) from public, anon;
grant execute on function public.admin_provider_english_status_read(uuid, text, integer) to authenticated, service_role;

-- 6 the existing job reads stored pages again (D5): one more argument, no new job -----------------------------------------------------------------------
select cron.alter_job((select jobid from cron.job where jobname = 'policy-add-tests'),
  command := $$select pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_facts_add_tests', 'limit', security.pipeline_num_v1('batch.policy_add_tests', 40)::int, 'reparse_limit', security.pipeline_num_v1('batch.policy_reparse', 20)::int))$$);
update pipeline.automation_catalogue set
  description = 'Hourly: reads approved English policy pages again from their stored copies (no Firecrawl, no AI) and adds tests the parser has learnt since approval (first the Duolingo English Test), only where the page''s IELTS for the level matches the approved policy. Each policy is checked once per parser version. It also reads stored English pages again with the current policy parser when their last reading gave no values or was rejected as one faculty row: a faculty or course-group table becomes a proposal for a Platform Admin to approve and bind (never approved automatically).'
 where jobname = 'policy-add-tests';
update pipeline.automation_catalogue set
  description = description || ' It also holds the switched-off search for providers that have no central English page (central.english_search_non_university) and limits English pages to central.english_provider_types.'
 where jobname = 'central-attach' and description not like '%central.english_search_non_university%';

-- 7 component register (housekeeping): new functions only; no job or table is added ------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.english_provider_in_scope_v1', 'Layer 2', 'Enrichment', 'Whether a provider type is in setting central.english_provider_types (the central English route)', 'active', '{}', '20261106550000'),
 ('function', 'security.english_group_match_v1', 'Layer 2', 'Enrichment', 'The person-bound course groups of an English policy that apply to a course (pure)', 'active', '{}', '20261106550000'),
 ('function', 'public.svc_provider_policy_reparse_next', 'Layer 2', 'Enrichment', 'Stored English pages to read again with the current policy parser (job policy-add-tests)', 'active', '{}', '20261106550000'),
 ('function', 'public.admin_provider_english_groups_set_v1', 'Layer 2', 'Enrichment', 'A Platform Admin binds the course groups of an English policy to courses (logged)', 'active', '{}', '20261106550000'),
 ('function', 'security.english_policy_status_v1', 'Layer 2', 'Enrichment', 'Per provider: stage on the English policy route, why there is no rule, next try', 'active', '{}', '20261106550000'),
 ('function', 'public.admin_provider_english_status_read', 'Layer 2', 'Enrichment', 'English policies panel: No rule yet, stages, jobs, credits, scope (read only)', 'active', '{}', '20261106550000')
on conflict (kind, name) do nothing;

-- 8 post-check ------------------------------------------------------------------------------------------------------------------------------------------
do $post$
begin
  if coalesce((select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'central.english_provider_types'), 'null'::jsonb) <> '["*"]'::jsonb then raise exception 'English post-check: provider scope is not today''s (every type)'; end if;
  if security.pipeline_num_v1('central.english_search_non_university', 1) <> 0 then raise exception 'English post-check: the non-university search must ship switched off'; end if;
  if (select command from cron.job where jobname = 'policy-add-tests') not like '%reparse_limit%' then raise exception 'English post-check: policy-add-tests lost its reparse argument'; end if;
  if (select count(*) from cron.job where jobname = 'policy-add-tests') <> 1 then raise exception 'English post-check: policy-add-tests must stay a single job'; end if;
  if pg_get_functiondef('security.policy_auto_approve_v1()'::regprocedure) not like '%course-group reading is never approved automatically%' then raise exception 'English post-check: automatic approval must exclude course groups'; end if;
end $post$;
