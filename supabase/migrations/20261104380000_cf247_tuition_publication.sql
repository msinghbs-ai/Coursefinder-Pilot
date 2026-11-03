-- CF-247 IQ-00116 (P1): Layer 4 tuition approvals in the catalogue but missing from the website projection (Platform Admin mandate 4 Nov 2026
-- 05:08 §7, §9; fingerprint l4_not_published:provider_current_tuition_validation:projection_has_no_fee).
-- Why (live, read-only, 4 Nov 2026 05:10-05:20 AEDT):
--   * IQ-00116 holds 2 approvals of 30 Oct 2026 (ACTS Auckland City Training School 2772, NZD 7,500 for 2026; Employment Focus Limited 2540,
--     NZD 14,000 for 2024). Both fee rows are active in catalogue.course_fees and are what security.course_fee_used_v1 (the fee rule Zoho reads
--     live) returns. Their search.course_documents rows were rebuilt at the approval's own second (generated_at = the fee's updated_at), so the
--     projection is not stale: the builder ran and left the fee out.
--   * The projection builder (search.refresh_course_enrichment_core_v1 and _core_scoped_v1, unchanged here) shows a provider fee only from a
--     source whose search.enrichment_source_gates row for provider_current_tuition is approved. Every other path that admits a fee opens its
--     source's gate when it writes (public.svc_fee_ai_record, the coverage admission); security.layer4_tuition_apply_impl writes the approved
--     fee under the review item's evidence source and refreshes the projection, but never opens that source. When the source had never been
--     opened by another writer (both cases are coverage-sweep sources of NZ providers) the approval stays in the catalogue only.
--   * Not the cause: fee year, audience, basis, validity window, holds or the refresh job. Across all 10,627 active courses whose page fee the
--     fee rule uses, 4 lack it in the projection, all for a closed source gate: these 2 approvals and 2 Federation University rows written by the
--     August 2026 Layer 2 path (no Layer 4 approval; left for a decision, below). Of 19 active Layer 4 fee approvals, 17 are published.
--   * The UNSW short courses of IQ-00111 no longer differ (694 UNSW courses: 1 difference, a 16-week practicum of AUD 830, below the website's
--     1,000 floor in api.website_v2_latest_fee; consumer API, frozen, not changed).
-- What (the apply path follows the established rule; the consumer API and the projection builder are not touched, G3):
--   1 security.layer4_tuition_gate_open_v1: opens a source's provider_current_tuition gate for a Layer 4 approval, only when every active
--     provider fee on that source is itself a Layer 4 approval (nothing unreviewed is published with it) and never over a blocked gate.
--   2 security.layer4_tuition_apply_impl (md5-guarded edit): calls 1 before its existing projection refresh and returns the gate result.
--   3 security.tuition_publication_rows_v1 / tuition_publication_check_v1 (read only): each active Layer 4 fee approval against the catalogue,
--     the projection (the fee in provider_tuition_options) and the fee rule Zoho reads (security.course_fee_used_v1), with its cause
--     (published, waiting, source_gate_closed, source_gate_blocked, outside_validity, audience, refresh_pending, course_not_projected,
--     course_not_active, projection_rule_other); with p_wide, every course whose page fee the fee rule uses but the projection lacks.
--   4 Remedy layer4_tuition_publication_repair (auto) for root cause layer4_tuition_source_gate_closed: opens the gates of approvals with a
--     closed gate through 1, refreshes those courses and the stale ones (layer4.tuition_publication_batch), and records the approvals' admission
--     check again; verified by 3 (no approval unpublished and no admission check still projection_has_no_fee). Ships ON: it only carries out
--     decisions a person already made at Layer 4, refuses mixed or blocked sources and spends nothing.
-- Not changed (a decision for the Platform Admin): the fee rule Zoho reads ignores source gates, so 2 Federation University courses
-- (119893C, 085212G) show the page fee in Zoho and the CRICOS total on the website. Opening that source or making the rule honour gates is a
-- publication decision, not a repair.
-- Replaces: security.layer4_tuition_apply_impl (same name; md5-guarded edit)
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object changes (G3): no api.*, website_*, zoho_edge_* function, table or column is altered.

do $g$
declare r record;
begin
  if to_regclass('pipeline.ops_remedies') is null then
    raise exception 'workstream A''s operations contract (migration 20261104010000) must be applied before this change';
  end if;
  -- the functions this change calls, unchanged since they were read live on 4 Nov 2026
  for r in select * from (values ('search.refresh_course_enrichment_scoped_v1(uuid[],boolean)', 'fb55e935a8d1c6c7b8cd1c476362cc60'),
                                 ('security.course_fee_used_v1(uuid)', 'e3cd801549ebf1883bb988fa24a3c909'),
                                 ('security.layer4_admission_record_v1(uuid)', 'b47d337ce40e075fe47d751ba564df64')) v(sig, m) loop
    if md5(pg_get_functiondef(r.sig::regprocedure)) <> r.m then
      raise exception 'live % differs from the definition this change was written against (md5 %)', r.sig, md5(pg_get_functiondef(r.sig::regprocedure)); end if;
  end loop;
end $g$;

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

-- 0 setting (G2; Settings > Pipeline settings, section Layer 4 readiness) -----------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'layer4.tuition_publication_batch', 'Layer 4: courses refreshed a run by the tuition publication repair',
  'The tuition publication repair opens the source of approved fees the website projection leaves out and refreshes at most this many courses in one run; the rest wait for the next run.',
  'number', to_jsonb(200), 1, 2000, 'courses', 1230, 'Layer 4 readiness', 'security.layer4_tuition_publication_repair_v1 (remedy layer4_tuition_publication_repair)',
  'IQ-00116, mandate 4 Nov 2026 05:08 §7: live 2 approvals; the scoped refresh of 200 courses stays well inside one controller run')
on conflict do nothing;

-- 1 the gate a Layer 4 tuition approval opens ------------------------------------------------------------------------------------------------
create or replace function security.layer4_tuition_gate_open_v1(p_source uuid, p_ref text) returns text
language plpgsql security definer set search_path to '' as $function$
-- CF-247 IQ-00116: the search projection shows a provider fee only from a source whose provider_current_tuition gate is approved
-- (search.enrichment_source_gates). A Layer 4 approval admits its fee, so its source is opened as every other fee writer opens its own
-- (public.svc_fee_ai_record, the coverage admission). Never over a blocked gate, and only when every active provider fee on the source is a
-- Layer 4 approval, so nothing unreviewed is published with it. Returns opened, already_open, gate_<status>, mixed_source or no_source.
declare v_status text; v_other int;
begin
  if p_source is null then return 'no_source'; end if;
  select g.gate_status into v_status from search.enrichment_source_gates g
   where g.projection_code = 'courses' and g.domain_code = 'provider_current_tuition' and g.source_id = p_source;
  if v_status = 'approved' then return 'already_open'; end if;
  if v_status is not null then return 'gate_' || v_status; end if;
  select count(*) into v_other from catalogue.course_fees f
   where f.source_id = p_source and f.fee_type = 'provider_current_tuition' and f.status = 'active'
     and coalesce(f.notes, '') not like 'CF-247 Layer 4 human decision; review item %';
  if v_other > 0 then return 'mixed_source'; end if;
  insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
  values ('courses', 'provider_current_tuition', p_source, 'approved',
          'CF-CHG-20260915-247; Layer 4 human decision (' || coalesce(p_ref, 'review item') || '); IQ-00116, mandate 4 Nov 2026 05:08 §7', now(), now(), now())
  on conflict do nothing;
  return 'opened';
end $function$;
revoke all on function security.layer4_tuition_gate_open_v1(uuid, text) from public, anon, authenticated;

-- 2 the apply path ---------------------------------------------------------------------------------------------------------------------------
select pg_temp.edit_once('security.layer4_tuition_apply_impl(uuid,uuid,jsonb,text)', 'ef89bdd9ad75a12ecd42ff83e5abc9cb', 'a6148e357decf7611eae1ebd2ce5ae76',
  array[array[
'  returning id into v_fee;
  perform search.refresh_course_enrichment_scoped_v1(array[v_item.entity_id], true);
  return jsonb_build_object(''course_fee_id'',v_fee,''fee_key'',v_key,''search_refreshed'',true);',
'  returning id into v_fee;
  -- CF-247 IQ-00116 (4 Nov 2026): the approval opens its source to the projection, as every fee writer does (security.layer4_tuition_gate_open_v1)
  v_gate := security.layer4_tuition_gate_open_v1(v_source, ''review item '' || v_item.id);
  perform search.refresh_course_enrichment_scoped_v1(array[v_item.entity_id], true);
  return jsonb_build_object(''course_fee_id'',v_fee,''fee_key'',v_key,''search_refreshed'',true,''source_gate'',v_gate);'],
   array['v_key text; v_fee uuid;', 'v_key text; v_fee uuid; v_gate text;']],
  array[1, 1]);

-- 3 the consistency check (read only) --------------------------------------------------------------------------------------------------------
create or replace function security.tuition_publication_rows_v1(p_course_ids uuid[] default null)
returns table(course_id uuid, fee_id uuid, review_item_id uuid, decision_id uuid, decided_at timestamptz, source_id uuid, amount numeric, currency text,
              fee_year int, basis text, gate text, projected boolean, doc_generated_at timestamptz, fee_updated_at timestamptz,
              rule_source text, rule_per_year numeric, rule_year int, rule_agrees boolean, cause text)
language sql stable security definer set search_path to '' as $function$
-- CF-247 IQ-00116: every active Layer 4 tuition approval (security.layer4_tuition_apply_impl names its review item in the fee's notes) against
-- the catalogue row, the search projection the website reads (the fee among provider_tuition_options) and the fee rule Zoho reads
-- (security.course_fee_used_v1), with the cause when the projection lacks it. Read only.
  with f as (
    select f.*, substring(f.notes from 'review item ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})')::uuid item
      from catalogue.course_fees f
     where f.fee_type = 'provider_current_tuition' and f.status = 'active' and f.notes like 'CF-247 Layer 4 human decision; review item %'
       and (p_course_ids is null or f.course_id = any (p_course_ids))),
  x as (
    select f.course_id cid, f.id fid, f.item, dd.did, dd.dat, f.source_id sid, f.amount amt, f.currency_code cur, f.fee_year yr, f.basis bas, f.audience aud,
           f.updated_at fupd, c.lifecycle_status life, doc.course_id doc_cid, doc.generated_at doc_at,
           (select g.gate_status from search.enrichment_source_gates g
             where g.projection_code = 'courses' and g.domain_code = 'provider_current_tuition' and g.source_id = f.source_id) gate,
           (select g.approved_at from search.enrichment_source_gates g
             where g.projection_code = 'courses' and g.domain_code = 'provider_current_tuition' and g.source_id = f.source_id) gate_at,
           ((f.valid_from is null or f.valid_from <= current_date) and (f.valid_to is null or f.valid_to >= current_date)) in_window,
           exists (select 1 from jsonb_array_elements(coalesce(doc.provider_tuition_options, '[]'::jsonb)) o
                    where (o->>'amount') ~ '^[0-9]+(\.[0-9]+)?$' and (o->>'amount')::numeric = f.amount
                      and nullif(o->>'fee_year', '')::int is not distinct from f.fee_year) projected,
           security.course_fee_used_v1(f.course_id) used
      from f
      join lateral (select y.id did, y.created_at dat from pipeline.layer4_decisions y
                     where y.review_item_id = f.item and y.action in ('approve', 'edit_and_approve') order by y.created_at desc limit 1) dd on true
      left join catalogue.courses c on c.id = f.course_id
      left join search.course_documents doc on doc.course_id = f.course_id)
  select x.cid, x.fid, x.item, x.did, x.dat, x.sid, x.amt, x.cur, x.yr, x.bas, coalesce(x.gate, 'none'), x.projected, x.doc_at, x.fupd,
         x.used->>'source', (x.used->>'per_year')::numeric, (x.used->>'year')::int,
         coalesce(x.used->>'source' = 'page' and (x.used->>'per_year')::numeric = x.amt and (x.used->>'year')::int is not distinct from x.yr, false),
         case when x.projected then 'published'
              when x.life is distinct from 'active' then 'course_not_active'
              when x.dat > now() - make_interval(mins => security.pipeline_num_v1('layer4.verify_wait_minutes', 90)::int) then 'waiting'
              when x.doc_cid is null then 'course_not_projected'
              when x.aud not in ('international', 'all') then 'audience'
              when x.gate is null then 'source_gate_closed'
              when x.gate <> 'approved' then 'source_gate_' || x.gate
              when not x.in_window then 'outside_validity'
              when x.doc_at is null or x.doc_at < greatest(x.fupd, x.gate_at) then 'refresh_pending'
              else 'projection_rule_other' end
    from x
$function$;
revoke all on function security.tuition_publication_rows_v1(uuid[]) from public, anon, authenticated;

create or replace function security.tuition_publication_check_v1(p_wide boolean default false) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- CF-247 IQ-00116: the tuition publication consistency check (catalogue, projection, fee rule Zoho reads). passed when no Layer 4 tuition
-- approval older than layer4.verify_wait_minutes is missing from the projection. With p_wide, also every active course whose page fee the fee
-- rule uses (security.course_fee_used_v1's selection) while the projection has no provider fee, by cause. Read only.
declare v jsonb; v_wide jsonb;
begin
  select jsonb_build_object(
    'at', now(),
    'approvals', count(*),
    'published', count(*) filter (where r.cause = 'published'),
    'waiting', count(*) filter (where r.cause = 'waiting'),
    'failing', count(*) filter (where r.cause not in ('published', 'waiting', 'course_not_active')),
    'by_cause', coalesce((select jsonb_object_agg(z.cause, z.n) from (select y.cause, count(*) n from security.tuition_publication_rows_v1(null) y group by 1) z), '{}'::jsonb),
    'rule_agrees', count(*) filter (where r.rule_agrees),
    'rule_differs', coalesce(jsonb_agg(jsonb_build_object('course', r.course_id, 'fee', r.amount, 'fee_year', r.fee_year, 'basis', r.basis, 'rule_source', r.rule_source,
                                                          'rule_per_year', r.rule_per_year, 'rule_year', r.rule_year)) filter (where not r.rule_agrees), '[]'::jsonb),
    'failing_rows', coalesce(jsonb_agg(jsonb_build_object('course', r.course_id, 'decision', r.decision_id, 'cause', r.cause, 'gate', r.gate, 'source', r.source_id,
                                                          'amount', r.amount, 'currency', r.currency, 'fee_year', r.fee_year))
                             filter (where r.cause not in ('published', 'waiting', 'course_not_active')), '[]'::jsonb))
    into v from security.tuition_publication_rows_v1(null) r;
  v := v || jsonb_build_object('passed', (v->>'failing')::int = 0);
  if p_wide then
    with pg as (
      select distinct on (f.course_id) f.course_id, f.source_id, f.valid_from, f.valid_to, f.notes
        from catalogue.course_fees f
       where f.fee_type = 'provider_current_tuition' and f.audience = 'international' and f.status = 'active' and f.amount > 0
         and f.basis in ('annual', 'indicative_annual', 'current indicative annual international tuition')
       order by f.course_id, f.fee_year desc nulls last, f.created_at desc),
    w as (
      select pg.*, d.has_provider_current_tuition has,
             case when (select g.gate_status from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'provider_current_tuition' and g.source_id = pg.source_id) is null then 'source_gate_closed'
                  when (select g.gate_status from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'provider_current_tuition' and g.source_id = pg.source_id) <> 'approved' then 'source_gate_blocked'
                  when not ((pg.valid_from is null or pg.valid_from <= current_date) and (pg.valid_to is null or pg.valid_to >= current_date)) then 'outside_validity'
                  else 'projection_rule_other' end cause,
             coalesce(pg.notes, '') like 'CF-247 Layer 4 human decision%' l4
        from pg join search.course_documents d on d.course_id = pg.course_id
        join catalogue.courses c on c.id = pg.course_id and c.lifecycle_status = 'active')
    select jsonb_build_object('page_fee_courses', count(*), 'missing_in_projection', count(*) filter (where not w.has),
             'missing_layer4', count(*) filter (where not w.has and w.l4),
             'by_cause', coalesce((select jsonb_object_agg(z.cause, z.n) from (select w2.cause, count(*) n from w w2 where not w2.has group by 1) z), '{}'::jsonb),
             'courses', coalesce(jsonb_agg(w.course_id) filter (where not w.has), '[]'::jsonb))
      into v_wide from w;
    v := v || jsonb_build_object('wide', v_wide);
  end if;
  return v;
end $function$;
revoke all on function security.tuition_publication_check_v1(boolean) from public, anon, authenticated;

-- 4 the remedy -------------------------------------------------------------------------------------------------------------------------------
create or replace function security.layer4_tuition_publication_repair_v1(p_issue bigint) returns jsonb
language plpgsql security definer set search_path to '' as $function$
-- Action of remedy layer4_tuition_publication_repair: for the Layer 4 tuition approvals the projection lacks, opens a closed source gate
-- (security.layer4_tuition_gate_open_v1: never a blocked or mixed source), refreshes those courses and the stale ones (at most
-- layer4.tuition_publication_batch), and records each approval's admission check again. Decides nothing; spends nothing.
declare r record; v_gates jsonb := '{}'::jsonb; v_res text; v_ids uuid[] := '{}'; v_decs uuid[] := '{}'; v_dec uuid; v_n int := 0;
        v_batch int := security.pipeline_num_v1('layer4.tuition_publication_batch', 200)::int;
begin
  for r in select x.source_id, min(x.review_item_id::text) ref, array_agg(x.course_id) cids, array_agg(x.decision_id) dids
             from security.tuition_publication_rows_v1(null) x where x.cause = 'source_gate_closed' group by 1 loop
    v_res := security.layer4_tuition_gate_open_v1(r.source_id, 'review item ' || r.ref);
    v_gates := jsonb_set(v_gates, array[v_res], to_jsonb(coalesce((v_gates->>v_res)::int, 0) + 1));
    if v_res = 'opened' then v_ids := v_ids || r.cids; v_decs := v_decs || r.dids; end if;
  end loop;
  -- the approvals whose projection is older than their fee or gate, and published ones whose admission check has not caught up
  select v_ids || coalesce(array_agg(y.course_id) filter (where y.cause = 'refresh_pending'), '{}'), v_decs || coalesce(array_agg(y.decision_id), '{}')
    into v_ids, v_decs
    from security.tuition_publication_rows_v1(null) y
   where y.cause = 'refresh_pending' or (y.cause = 'published' and exists (
           select 1 from pipeline.layer4_admission_checks c where c.decision_id = y.decision_id and c.result = 'admitted_not_published'));
  v_ids := array(select distinct unnest(v_ids)); v_decs := array(select distinct unnest(v_decs));
  -- refresh them (the batch), then record the approvals' admission checks
  if cardinality(v_ids) > 0 then
    v_ids := v_ids[1:v_batch];
    perform search.refresh_course_enrichment_scoped_v1(v_ids, true);
  end if;
  foreach v_dec in array v_decs loop
    perform security.layer4_admission_record_v1(v_dec);
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'changed', coalesce((v_gates->>'opened')::int, 0) > 0 or cardinality(v_ids) > 0,
                            'evidence', jsonb_build_object('gates', v_gates, 'refreshed', cardinality(v_ids), 'rechecked', v_n,
                                                           'check', security.tuition_publication_check_v1(false) - 'rule_differs'));
end $function$;
revoke all on function security.layer4_tuition_publication_repair_v1(bigint) from public, anon, authenticated;

create or replace function security.layer4_tuition_publication_verify_v1(p_issue bigint) returns jsonb
language plpgsql stable security definer set search_path to '' as $function$
-- Verification of layer4_tuition_publication_repair: passed when no Layer 4 tuition approval is missing from the projection
-- (security.tuition_publication_check_v1) and no admission check still reads projection_has_no_fee; waiting while only young approvals remain.
declare v jsonb := security.tuition_publication_check_v1(false); v_left int;
begin
  select count(*) into v_left from pipeline.layer4_admission_checks c
   where c.field_code = 'provider_current_tuition_validation' and c.result = 'admitted_not_published' and c.reason = 'projection_has_no_fee';
  return jsonb_build_object('passed', (v->>'passed')::boolean and v_left = 0,
    'measure', jsonb_build_object('condition_cleared', (v->>'passed')::boolean and v_left = 0, 'waiting', (v->>'passed')::boolean and v_left = 0 and (v->>'waiting')::int > 0,
                                  'approvals', v->'approvals', 'published', v->'published', 'failing', v->'failing', 'by_cause', v->'by_cause', 'admission_checks_left', v_left),
    'evidence', format('%s of %s Layer 4 tuition approval(s) on the website projection; %s failing (%s); %s admission check(s) still projection_has_no_fee',
                       v->>'published', v->>'approvals', v->>'failing', v->'by_cause', v_left));
end $function$;
revoke all on function security.layer4_tuition_publication_verify_v1(bigint) from public, anon, authenticated;

-- 5 root cause and remedy (workstream A's contract) ------------------------------------------------------------------------------------------
select security.ops_root_cause_register_v1('layer4_tuition_source_gate_closed', jsonb_build_object('class', 'rule',
  'title', 'A Layer 4 tuition approval is not on the website because its source is not open to the projection',
  'description', 'security.layer4_tuition_apply_impl wrote the approved fee under the review item''s evidence source but did not open that source''s provider_current_tuition gate (search.enrichment_source_gates), which the projection requires; every other fee writer opens its own. Live 4 Nov 2026: IQ-00116, 2 approvals of 30 Oct on coverage-sweep sources of NZ providers. Fixed in the apply path (v2.15.459 candidate); the remedy opens the gates of approvals already saved, never a blocked source or one holding unreviewed fees.',
  'detect', jsonb_build_object('priority', 47, 'confidence', 0.9,
                               'any', jsonb_build_array(jsonb_build_object('fingerprint_like', jsonb_build_array('l4\_not\_published:provider\_current\_tuition\_validation:projection\_has\_no\_fee'))))));

select security.ops_remedy_register_v1('layer4_tuition_publication_repair', jsonb_build_object(
  'title', 'Open the source of approved tuition fees to the projection, refresh those courses and check the approvals again',
  'treats', jsonb_build_array('layer4_tuition_source_gate_closed'), 'authority', 'auto',
  'action_fn', 'security.layer4_tuition_publication_repair_v1(bigint)', 'verify_fn', 'security.layer4_tuition_publication_verify_v1(bigint)',
  'max_attempts_key', 'layer4.remedy_max_attempts', 'cooldown_key', 'layer4.remedy_cooldown_minutes',
  'notes', 'Carries out Layer 4 decisions already made: opens a gate only when every active provider fee on the source is a Layer 4 approval and the gate is not blocked; decides, admits and spends nothing. A mixed or blocked source stays failing and the issue goes to a person.'));
