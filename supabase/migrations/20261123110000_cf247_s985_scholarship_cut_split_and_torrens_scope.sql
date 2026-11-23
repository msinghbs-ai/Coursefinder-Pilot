-- CF-247 s985 (S2-Build, scholarships owner; Platform Admin 23 Nov 2026 13:13 AEDT: "start the scholarship coverage expansion (s1001) for Charles
-- Darwin, Lincoln, and Torrens. Keep the M3 telemetry guardrail in scope ... so ai:scholarship_extraction stops truncating mid-JSON"). First slice of
-- the s1001 work; the P1 to P10 reconciliation and its thirteen-case fixture stay under spec s1001.
-- Measured live 23 Nov 2026 13:25 to 13:50 AEDT (rolled-back read-backs; head 20261123060000):
-- 1. Extraction cut-off. In 48 hours 68 of 430 scholarship_extraction calls (15.8%) stopped at the answer limit (reading.answer_tokens.scholarship_page
--    4,500; successful answers 1,518 tokens at the 90th percentile). All were candidate-page reads (run_kind admit/reread) of pages that list many
--    awards (school scholarship pages: Peninsula Grammar, St Andrew's Cathedral School, Geelong Grammar). A cut answer is "unsettled" and goes to the
--    next model in the chain as the same whole-page request, which cut again (21 items). The long-page recovery variant sectioned-v1 (13 Nov 2026,
--    sch-extract.ts: the page in two smaller calls, part A identity and eligibility, part B benefits and payment, merged into one answer) was given
--    only to detail items of scholarships already held. A higher limit was not chosen: the cut answers are runaway multi-award answers, so a higher
--    limit would make each cut dearer, not complete.
--    public.svc_scholarship_ai_record (md5-guarded, two fragments): when an answer was cut at the limit, the item that goes to the next model carries
--    recovery = 'sectioned-v1', so it is read in two smaller calls. The worker already reads any item with that variant (coverage-sweep v0.83.0 and
--    later; awardSection takes the start of the page when no name is held). Calls per item stay the same or fewer (one split read instead of a
--    repeated whole-page cut).
-- 2. Torrens University Australia (REQ-95). Its 3 international scholarship pages (stored copy and AI reading held) are rejected as "not a
--    university provider in a scholarship country": its registered name joins its trading names ("Torrens University Australia; Torrens University
--    Language Centre; Chifley Business School ...") and the university test refuses any name containing "Language Centre". The fix for exactly this
--    case exists (IQ-00215, 4 Nov 2026: security.scholarship_university tests the legal name, the first of the joined names) and ships off
--    ("admission scope"). Switched on at the Platform Admin's instruction to cover Torrens; read live, it brings exactly one provider into scope:
--    Torrens. The candidates rejected only by that test are admitted again through the canonical admission function
--    (security.scholarship_admit_from_provider_page_v1), with every other check unchanged.
-- Not changed: Charles Darwin and Lincoln. Their candidates are rejected by their own pages (domestic only, international not stated, not a
-- scholarship page) and none by a cut answer; their international awards sit on listing pages that need the listing reader (job
-- scholarship-listing is off since 23 Nov 08:29), a discovery gap recorded for the next slice. A nationality rule was measured and not built: the
-- readings mix alpha-2 and alpha-3 codes and regions, so it would publish domestic awards (AUS read as not the host AU).
-- G1: no job. G2: no new value (the switch is the existing setting). G3: no consumer object (75/48 before and after). Manual locks untouched. $0
-- Firecrawl; AI calls only through the existing scheduled extraction within its ceiling. Nothing dropped or removed.
-- Replaces: the whole-page retry of a cut candidate-page answer (now the two-part read); sch_cov.legal_name_identity_on 0 -> 1.
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function edit and the setting

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s985_locks on commit drop as select count(*) n from pipeline.manual_locks;

-- 1. a cut answer goes to the next model as the two-part read
do $e$
declare v_sig regprocedure := (select p.oid::regprocedure from pg_proc p where p.proname = 'svc_scholarship_ai_record' and p.pronamespace = 'public'::regnamespace);
        v_def text; v_n int; r record;
begin
  v_def := pg_get_functiondef(v_sig);
  if position('s985 (23 Nov 2026' in v_def) > 0 then raise notice 's985 edit: already applied'; return; end if;
  if md5(v_def) <> 'fa3345b7e0fe4ba9b6abafe2ebec4f6a' then
    raise exception 'guard: live public.svc_scholarship_ai_record differs from the definition this change edits (live md5 %)', md5(v_def);
  end if;
  for r in select * from (values
    (1, $o$scholarship_id, provider_id, url, step, storage_path, root_id, fresh_read, read_request_id)
    values (v_next, q.prompt_version$o$,
        $n$scholarship_id, provider_id, url, step, storage_path, root_id, fresh_read, read_request_id, recovery)
    values (v_next, q.prompt_version$n$),
    (2, $o$coalesce(p_storage_path, q.storage_path), coalesce(q.root_id, q.id), q.fresh_read and coalesce(p_storage_path, q.storage_path) is null, q.read_request_id);$o$,
        $n$coalesce(p_storage_path, q.storage_path), coalesce(q.root_id, q.id), q.fresh_read and coalesce(p_storage_path, q.storage_path) is null, q.read_request_id,
            -- s985 (23 Nov 2026): an answer cut at the limit is read next as the two-part read (sectioned-v1), not the same whole-page request
            case when coalesce(p_error, '') like 'held_partial: output_truncated%' and coalesce(q.prompt_version, 0) >= 3 then 'sectioned-v1' else q.recovery end);$n$)) v(n, old, new) order by n
  loop
    v_n := (length(v_def) - length(replace(v_def, r.old, ''))) / length(r.old);
    if v_n <> 1 then raise exception 'guard: fragment % of public.svc_scholarship_ai_record is found % times', r.n, v_n; end if;
    v_def := replace(v_def, r.old, r.new);
  end loop;
  execute v_def;
end $e$;

-- 2. Torrens: the legal-name university test (IQ-00215) switched on, then the candidates refused only by the old test are admitted again
update pipeline.platform_toolset_settings set value = to_jsonb(1), updated_at = now(),
       reason = 'CF-247 s985 (Platform Admin 23 Nov 2026 13:13: scholarship coverage for Torrens): a provider whose record joins its trading names is tested on its legal name; brings Torrens University Australia into scope'
 where toolset_key = 'pipeline' and key = 'sch_cov.legal_name_identity_on' and value = to_jsonb(0);
insert into pipeline.admin_control_events (area, action, target, detail, actor)
values ('settings', 'migration', 'pipeline.platform_toolset_settings', jsonb_build_object('key', 'sch_cov.legal_name_identity_on', 'before', 0, 'after', 1,
        'reason', 'Platform Admin 23 Nov 2026 13:13: scholarship coverage for Torrens (s985)', 'migration', '20261123110000'), security.system_actor_id());

do $r$
declare c record; v jsonb; n int := 0;
begin
  for c in select x.id from pipeline.scholarship_page_candidates x
            where x.admit_status = 'rejected' and x.admit_reasons::text like '%not a university provider in a scholarship country%'
              and security.scholarship_university(x.provider_id)
  loop
    v := security.scholarship_admit_from_provider_page_v1(c.id);
    n := n + 1;
    raise notice 's985 re-admit candidate %: %', c.id, left(v::text, 300);
  end loop;
  raise notice 's985 re-admitted % candidate(s)', n;
end $r$;

do $p$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from pg_temp.s985_locks) then raise exception 'post-check: manual locks changed'; end if;
  if position('s985 (23 Nov 2026' in (select pg_get_functiondef(p.oid) from pg_proc p where p.proname = 'svc_scholarship_ai_record' and p.pronamespace = 'public'::regnamespace)) = 0 then
    raise exception 'post-check: the record function was not edited';
  end if;
  if not security.scholarship_university('fec52f92-a8a3-4de8-a862-06f355e4e2f7') then raise exception 'post-check: Torrens is still out of scholarship scope'; end if;
end $p$;
