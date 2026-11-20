-- CF-247 s884 to s886 (session S1-ELR-Central, Platform Admin 20 Nov 2026 22:07 AEDT, "Decision approved: Yes — populate the remaining Table 1 English gaps
-- (6,203 courses: 3,769 AU, 1,093 NZ, 1,341 CA) from each university's central English requirements page via the governed provider English policy route, using $0 AI
-- and $0 Firecrawl spend over already-stored pages"). English language requirements only.
--
-- Found live (rolled-back probes, 20 Nov 2026 22:10 to 22:40 AEDT; head 20261120200000): Table 1 is 6,160 active AU, NZ and CA courses on 792 providers.
--   - 115 providers (1,829 courses) have an approved central English policy, and none of those courses is waiting to cascade: the plans hold them because the level is not
--     covered (VET, certificates, non-AQF: 1,173), the policy gives no research requirement (362) or no default for the level (266), the course is named (186), or it is
--     a double degree or exit award (61). 0 have the outcome "write".
--   - 15 providers (648 courses) have a central reading waiting for a person; 69 (1,051) have a stored central page whose reading found no values; 70 (346) have a
--     central page found but not stored (needs Firecrawl: not in this $0 lane); 523 (2,286) have no central page.
--
-- What changes:
--   (s884) reader elr-central-v1.0 (coverage-sweep/elr-central-reader.ts, read-only worker mode elr_central_read): the requirement for each tier the stored central page
--          states (undergraduate, postgraduate coursework, higher degree by research, VET and diploma), with verbatim quotes, strict tiers, conflicts left out, and
--          regulated disciplines reported (discipline_higher) instead of used as a default.
--   (s885) the governed route: security.elr_central_record_v1 turns a provider's readings into one english_policy proposal (parser elr-central-v1.0, status proposed) holding
--          only the tiers the provider's approved policy does not already give (never a replacement of an approved policy), with that policy's named courses and exceptions
--          carried so the plan still holds them. security.policy_auto_approve_v1 approves such a reading only when it has no conflict and no other reading of the university
--          waits for a person (setting central.auto_approve_elr_central). security.provider_english_plan_v1 gives VET and diploma courses a VET default only when the policy
--          states one, and holds a course of a regulated discipline the page gives higher bands for; the existing plan rules keep tiers strict, and the existing apply writes
--          only "write" outcomes (no row, no lock, no review), so no course rule and no manual lock is touched.
--   (s886) one schedule: the existing job elr-det-sweep also reads the central pages back, records them, applies a bounded number of approved elr-central policies a run
--          (security.provider_english_apply_v1) and sends each regulated-discipline hold to Layer 4. No new cron job (the active job count does not change).
--          security.provider_english_apply_all_v1 (job provider-english-defaults) skips elr-central policies so its run time does not grow with them.
-- Objects (no new public function, table or view; G3 stays 75/48): tables pipeline.elr_central_reads, pipeline.elr_central_applies; column pipeline.elr_det_requests.mode;
--   functions security.elr_central_claim_v1, security.elr_central_record_v1; replaced security.elr_det_sweep_tick_v1, security.elr_det_status_v1,
--   security.provider_english_plan_v1, security.provider_english_apply_v1, security.provider_english_apply_all_v1, security.policy_auto_approve_v1 (each md5-checked first);
--   settings elr_central.on, batch.elr_central, elr_central.apply_per_run, elr_central.reapply_hours, elr_central.l4_per_run, central.auto_approve_elr_central.
-- G1: no new job; the elr-det-sweep catalogue line is updated. G2: every size and limit is a setting. Spend: none (no model, no Firecrawl).
-- Parity: head 20261120200000 read live 20 Nov 2026 22:10 AEDT; this file is numbered strictly above it.
-- Replaces: the per-proposal application of elr-central policies inside provider_english_apply_all_v1 (they are applied by the sweep instead).
-- Retires: nothing. Nothing dropped, deleted or renamed.
-- Rollback: elr_central.on 0 stops reading; central.auto_approve_elr_central 0 leaves readings for a person; an elr-central policy is rejected in Universities › English
--   like any other, and its rows carry source_requirement_key 'policy:<proposal id>:<test>'.
set local lock_timeout = '5s';
set local statement_timeout = '240s';  -- fixed: the post-check runs the largest providers' English plans twice (before and after) to compare them

do $g$
declare v jsonb := security.consumer_api_check_v1(); r record;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  for r in select * from (values ('security.provider_english_plan_v1(uuid)', '737f92c05ae9d61a95dfb855b6fe35e3'), ('security.provider_english_apply_v1(uuid)', '65f5d9c65057ce4acb67c344d854a1d5'),
                                 ('security.provider_english_apply_all_v1()', 'a0d9a19695fd50416b65460b3149a2df'), ('security.policy_auto_approve_v1()', 'f8f0b8dd7c793fb2e11c3be55cfc8045'),
                                 ('security.elr_det_sweep_tick_v1()', 'e08ac04e1c4c42239dab5a3040c10db4'), ('security.elr_det_status_v1()', '00d5cfd704afe3730aca8a5d71380ce2')) v(f, h) loop
    if md5(pg_get_functiondef(r.f::regprocedure)) <> r.h then raise exception 'guard: % is not the text this change was written against', r.f; end if;
  end loop;
end $g$;

create temp table s885_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s885_cron on commit drop as select count(*) n from cron.job where active;
-- the plans of the largest providers before the change, kept for the post-check comparison
create temp table s885_plan_before (proposal_id uuid, h text) on commit drop;
do $b$
declare r record; v_h text;
begin
  for r in select o2.id from pipeline.provider_policy_proposals o2 where o2.kind = 'english_policy' and o2.status = 'approved'
            order by (select count(*) from catalogue.courses c where c.provider_id = o2.provider_id and c.lifecycle_status = 'active') desc, o2.id limit 8 loop
    select md5(coalesce(string_agg(t::text, '|' order by t.course_id), '')) into v_h from security.provider_english_plan_v1(r.id) t;
    insert into s885_plan_before values (r.id, v_h);
  end loop;
end $b$;

-- (s885) the plan: VET tier and regulated-discipline hold (live text with three additions)
CREATE OR REPLACE FUNCTION security.provider_english_plan_v1(p_proposal_id uuid)
 RETURNS TABLE(course_id uuid, title text, study_level text, plan text, reason text, requirements jsonb, existing jsonb, outcome text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'ref', 'security'
AS $function$
declare x pipeline.provider_policy_proposals%rowtype; v_named jsonb; v_defaults jsonb; v_has_bindings boolean; v_other_bindings boolean;
        v_disc text[];  -- s885: regulated disciplines the policy's central page gives higher bands for (elr-central-v1.0 readings only)
        -- CF-247 ENG 8 Nov 2026: english.default_after_withdrawn_reading (off = a withdrawn row of any kind counts as a reading, as before)
        v_wd_off boolean := security.pipeline_num_v1('english.default_after_withdrawn_reading', 0) < 1;
begin
  select * into x from pipeline.provider_policy_proposals where id = p_proposal_id;
  if x.id is null or x.kind <> 'english_policy' then raise exception 'not an English policy proposal'; end if;
  v_defaults := coalesce(x.proposal->'defaults', '{}'::jsonb);
  v_disc := array(select distinct d->>'discipline' from jsonb_array_elements(case when jsonb_typeof(x.proposal->'discipline_higher') = 'array' then x.proposal->'discipline_higher' else '[]'::jsonb end) d
                   where d->>'discipline' is not null);
  -- s840: whether this policy, or another approved English policy of the same provider, has any course-group binding (security.english_group_match_v1 answers [] without one)
  v_has_bindings := jsonb_typeof(x.proposal->'group_bindings') = 'array' and jsonb_array_length(x.proposal->'group_bindings') > 0;
  v_other_bindings := exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = x.provider_id and o.kind = 'english_policy' and o.status = 'approved' and o.id <> x.id
                               and jsonb_typeof(o.proposal->'group_bindings') = 'array' and jsonb_array_length(o.proposal->'group_bindings') > 0);
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
    -- s840: the title key is security.english_title_key written out in place (the function carries SET search_path, so each of the provider's course rows paid a
    -- configuration switch for it); the post-check proves the two agree for every active course of the largest providers
    select co.id, co.canonical_title t,
           btrim(regexp_replace(regexp_replace(regexp_replace(
             replace(regexp_replace(lower(coalesce(co.canonical_title,'')),'\(\s*\d+\s+units(\s+and\s+\d+\s+units)?\s*\)','','g'),'&',' and '),
             '[^a-z0-9/]+',' ','g'),' ?/ ?','/','g'),'\s+',' ','g')) k,
           sl.code lvl, ff.path field_path
      from catalogue.courses co left join ref.study_levels sl on sl.id = co.study_level_id left join ref.fields_of_study ff on ff.id = co.primary_field_id
     where co.provider_id = x.provider_id and co.lifecycle_status = 'active'),
  c as materialized (
    select c0.*, array(select distinct t from unnest(regexp_split_to_array(c0.k, '[ /]+')) t where t not in ('of', 'and', 'in', 'the', '')) toks,
           case when c0.lvl in ('bachelor', 'bachelor_honours', 'associate_degree') then 'undergraduate'
                when c0.lvl in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate'
                when c0.lvl in ('doctorate', 'masters_research') then 'research'
                -- s885 (20 Nov 2026): VET and diploma courses take a VET default, only when the policy states one (a policy without it holds them as before)
                when c0.lvl in ('diploma', 'advanced_diploma', 'certificate', 'certificate_ii', 'certificate_iii', 'certificate_iv') and jsonb_typeof(v_defaults->'vet') = 'array' then 'vet' end grp,
           -- s885: the regulated discipline of the course, asked only when the central page gave higher bands for one
           case when cardinality(v_disc) = 0 then null
                when c0.t ~* '\mnurs' then 'nursing' when c0.t ~* '\mmidwi' then 'midwifery' when c0.t ~* '\m(medicine|medical|mbbs)\M' then 'medicine'
                when c0.t ~* '\m(allied health|physiotherap\w*|occupational therap\w*|speech patholog\w*|pharmac\w*|dentist\w*|dental|optometr\w*|podiatr\w*|paramedic\w*|radiograph\w*|dietetic\w*|psycholog\w*)' then 'allied health'
                when c0.t ~* '\m(teach\w*|education)\M' then 'education' when c0.t ~* '\m(laws?|juris doctor|legal practice)\M' then 'law' when c0.t ~* '\msocial work' then 'social work' end disc,  -- CF-247 15 Oct: research degrees take the policy's research default
           (select coalesce(jsonb_object_agg(et.code, r.overall_score), '{}'::jsonb) from catalogue.course_english_requirements r
              join ref.english_tests et on et.id = r.english_test_id where r.course_id = c0.id and r.status = 'active') ex,
           exists (select 1 from catalogue.course_english_requirements r where r.course_id = c0.id
                    and (v_wd_off or r.status = 'active' or coalesce(r.source_requirement_key, '') like 'policy:%')) any_row,
           -- the scores of withdrawn readings the course page gave (a policy's own withdrawn rows are not here: they keep blocking)
           case when v_wd_off then '{}'::jsonb else (select coalesce(jsonb_object_agg(et.code, r.overall_score), '{}'::jsonb) from catalogue.course_english_requirements r
              join ref.english_tests et on et.id = r.english_test_id
             where r.course_id = c0.id and r.status = 'withdrawn' and coalesce(r.source_requirement_key, '') not like 'policy:%') end wd_ex,
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
           -- s840 (20 Nov 2026): the match is asked only when this policy has course-group bindings (none of the 180 approved policies had any; every call answered [] at a cost)
           case when c.grp in ('undergraduate', 'postgraduate') and v_has_bindings then security.english_group_match_v1(x.proposal, c.t, c.field_path, c.grp) else '[]'::jsonb end grp_hits
      from c),
  m2 as (
    select m.*, g.n grp_n, g.name grp_name,
           -- another approved policy of this provider names this course with its own scores: that is more specific than a group
           (g.n = 1 and exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = x.provider_id and o.kind = 'english_policy' and o.status = 'approved' and o.id <> x.id
              and exists (select 1 from jsonb_array_elements(coalesce(o.proposal->'exceptions', '[]'::jsonb)) e where jsonb_typeof(e->'reqs') = 'array' and jsonb_array_length(e->'reqs') > 0 and security.english_title_key(e->>'name') = m.k))) named_elsewhere,
           -- another approved policy of this provider has a bound course group for this course: it takes the course, so this policy's level default does not
           -- s840: only the other policies that have course-group bindings are asked (bindings_other, read once), so a provider without bindings costs nothing here
           (case when v_other_bindings and m.grp in ('undergraduate', 'postgraduate') then exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = x.provider_id and o.kind = 'english_policy' and o.status = 'approved' and o.id <> x.id
              and jsonb_typeof(o.proposal->'group_bindings') = 'array' and jsonb_array_length(o.proposal->'group_bindings') > 0
              and jsonb_array_length(security.english_group_match_v1(o.proposal, m.t, m.field_path, m.grp)) > 0) else false end) other_group
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
                -- s885: a regulated discipline the central page gives higher bands for is never given the level default; a person sets it (Layer 4)
                when m.disc is not null and m.disc = any (v_disc) then 'held|regulated discipline (' || m.disc || '): the central page gives it higher bands'
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
              when exists (select 1 from jsonb_array_elements(q.reqs) r where q.wd_ex ? (r->>'test_code') and (q.wd_ex->>(r->>'test_code'))::numeric <> (r->>'overall_score')::numeric) then 'differs'
              when q.locked then 'set_by_hand'
              when q.in_review then 'in_review'
              when q.in_l3 or q.page_waiting then 'waiting'
              else 'write' end
    from q;
end $function$
;

-- (s886) the apply note names the VET and diploma tier (live text with one addition)
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
                          else 'Default for ' || case when r.study_level in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate coursework' when r.study_level in ('doctorate', 'masters_research') then 'research' when r.study_level in ('diploma', 'advanced_diploma', 'certificate', 'certificate_ii', 'certificate_iii', 'certificate_iv') then 'VET and diploma' else 'undergraduate' end
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
end $function$
;

-- (s886) the provider-english-defaults run leaves elr-central policies to the sweep (live text with one addition)
CREATE OR REPLACE FUNCTION security.provider_english_apply_all_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'pipeline', 'security'
AS $function$
declare r record; v jsonb; v_total int := 0; v_n int := 0; v_failed int := 0;
begin
  -- s885: elr-central-v1.0 policies are applied by the English requirement sweep in bounded runs (security.elr_det_sweep_tick_v1), so this run's time does not grow with them
  for r in select id from pipeline.provider_policy_proposals where kind = 'english_policy' and status = 'approved' and parser is distinct from 'elr-central-v1.0' order by decided_at loop
    begin
      v := security.provider_english_apply_v1(r.id); v_total := v_total + coalesce((v->>'written')::int, 0); v_n := v_n + 1;
    exception when others then
      v_failed := v_failed + 1;
      update pipeline.provider_policy_proposals set apply_summary = coalesce(apply_summary, '{}'::jsonb) || jsonb_build_object('last_error', left(sqlerrm, 200), 'last_failed_at', now()), updated_at = now() where id = r.id;
    end;
  end loop;
  return jsonb_build_object('proposals', v_n, 'written', v_total, 'not_applied', v_failed);
end $function$
;

-- (s885) governed approval of deterministic central readings (live text with one addition)
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
  -- CF-247 F-INT.01/SRC-01 (9 Nov 2026): official main teaching calendars are qualified by rule when central.calendar_qualify_main_teaching = 1 (default 0: returns at once);
  -- a failure is recorded in pipeline.calendar_qualify_runs inside the function and never stops the approvals below
  perform security.calendar_qualify_v1();
  if not coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'central.auto_approve'), false) then
    return jsonb_build_object('off', true);
  end if;
  for r in select x.* from pipeline.provider_policy_proposals x
             left join pipeline.enrich_focus_providers f on f.provider_id = x.provider_id
            where x.status = 'proposed' and x.kind in ('english_policy', 'intake_calendar')
              -- CF-247 6 Nov 2026 (English requirements, decision D2): a faculty or course-group reading is never approved automatically; a person approves it and binds its groups
              and (x.kind <> 'english_policy' or jsonb_array_length(case when jsonb_typeof(x.proposal->'groups') = 'array' then x.proposal->'groups' else '[]'::jsonb end) = 0)
              and (x.parser like 'ai:%'
                   -- s885 (Platform Admin 20 Nov 2026 22:07, "Decision approved: populate the remaining Table 1 English gaps from each university's central English requirements page"):
                   -- a deterministic elr-central-v1.0 reading with every value quoted, no conflict, and no other reading of the university waiting for a person
                   or (x.kind = 'english_policy' and x.parser = 'elr-central-v1.0' and security.pipeline_num_v1('central.auto_approve_elr_central', 1) = 1
                       and jsonb_array_length(case when jsonb_typeof(x.proposal->'conflicts') = 'array' then x.proposal->'conflicts' else '[]'::jsonb end) = 0
                       and not exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = x.provider_id and o.kind = 'english_policy' and o.status = 'proposed' and o.id <> x.id))
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
end $function$
;

-- (s885) the working tables
create table if not exists pipeline.elr_central_reads (
  fact_source_id uuid not null references pipeline.provider_fact_sources(id) on delete cascade,
  extractor      text not null,
  provider_id    uuid not null,
  evidence_id    uuid,
  outcome        text not null default 'sent' check (outcome in ('sent', 'read', 'lost', 'failed')),
  sha256         text,
  reading        jsonb,
  result         text,
  proposal_id    uuid,
  request_id     bigint,
  sent_at        timestamptz not null default now(),
  read_at        timestamptz,
  primary key (fact_source_id, extractor)
);
comment on table pipeline.elr_central_reads is 'CF-247 s885: each stored central English requirements page the deterministic central reader (elr-central) was sent or has read, with its tier reading and what came of it (the proposal it made, or why none). Lets the sweep resume and never read a page twice.';
create index if not exists elr_central_reads_request on pipeline.elr_central_reads (request_id) where outcome = 'sent';
create index if not exists elr_central_reads_provider on pipeline.elr_central_reads (provider_id);
alter table pipeline.elr_central_reads enable row level security;
revoke all on pipeline.elr_central_reads from public, anon, authenticated;

create table if not exists pipeline.elr_central_applies (
  proposal_id  uuid primary key references pipeline.provider_policy_proposals(id) on delete cascade,
  applied_at   timestamptz not null default now(),
  runs         integer not null default 1,
  written      integer not null default 0,
  layer4       integer not null default 0,
  last_error   text
);
comment on table pipeline.elr_central_applies is 'CF-247 s886: when the English requirement sweep last applied each approved elr-central policy, what it wrote and how many regulated-discipline courses it sent to Layer 4.';
alter table pipeline.elr_central_applies enable row level security;
revoke all on pipeline.elr_central_applies from public, anon, authenticated;

alter table pipeline.elr_det_requests add column if not exists mode text not null default 'elr_det_read';
comment on column pipeline.elr_det_requests.mode is 'CF-247 s886: the worker mode of the call (elr_det_read for course pages, elr_central_read for central English pages).';

-- (G2) settings
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'elr_central.on', 'English requirement sweep: read central English pages',
  '1: each run of elr-det-sweep also reads stored central English requirement pages of universities that still have courses with no English requirement, and applies the approved readings. 0: it does not.',
  'number', to_jsonb(1), 0, 1, 'switch', 657, 'Admission checks', 'security.elr_det_sweep_tick_v1', 'CF-247 s886 (Platform Admin 20 Nov 2026 22:07): populate Table 1 from central pages'),
 ('pipeline', 'batch.elr_central', 'English requirement sweep: universities a run (central pages)',
  'Universities whose stored central English pages are read in one run (all of a university''s pages go in the same call).', 'number', to_jsonb(6), 1, 15, 'universities', 658, 'Admission checks',
  'security.elr_det_sweep_tick_v1; security.elr_central_claim_v1', 'CF-247 s886: bounded, low-IOPS batches'),
 ('pipeline', 'elr_central.apply_per_run', 'English requirement sweep: central policies applied a run',
  'Approved central-page policies (elr-central) applied to their courses in one run.', 'number', to_jsonb(2), 1, 10, 'policies', 659, 'Admission checks', 'security.elr_det_sweep_tick_v1', 'CF-247 s886: bounded'),
 ('pipeline', 'elr_central.reapply_hours', 'English requirement sweep: re-apply a central policy after',
  'A central-page policy is applied again after this many hours, so courses added later get its requirement.', 'number', to_jsonb(6), 1, 168, 'hours', 660, 'Admission checks', 'security.elr_det_sweep_tick_v1', 'CF-247 s886'),
 ('pipeline', 'elr_central.l4_per_run', 'English requirement sweep: regulated-discipline courses sent to Layer 4 a run',
  'Most courses of a regulated discipline (nursing, midwifery, medicine, allied health, teaching, law, social work) sent to Layer 4 in one run when the central page gives them higher bands.',
  'number', to_jsonb(50), 0, 200, 'courses', 661, 'Admission checks', 'security.elr_det_sweep_tick_v1', 'CF-247 s886: regulated discipline exceptions held in Layer 4'),
 ('pipeline', 'central.auto_approve_elr_central', 'Central pages: approve deterministic English readings automatically',
  '1: a deterministic central-page English reading (elr-central-v1.0) with every value quoted, no conflict and no other reading of the university waiting for a person is approved by policy-auto-approve (the course-page disagreement check still applies). 0: a person approves it.',
  'number', to_jsonb(1), 0, 1, 'switch', 662, 'Admission checks', 'security.policy_auto_approve_v1', 'CF-247 s885 (Platform Admin 20 Nov 2026 22:07): decision approved, populate Table 1 through the governed policy route')
on conflict do nothing;

-- (s885) the next universities with stored central English pages to read: still have a course with no English requirement, no elr-central policy yet, page not read
create or replace function security.elr_central_claim_v1(p_providers integer) returns table (fact_source_id uuid, provider_id uuid, evidence_id uuid, storage_path text)
language sql stable security definer set search_path to ''
as $f$
  with pv as (
    select f.provider_id from pipeline.provider_fact_sources f
      join catalogue.providers p on p.id = f.provider_id
      join pipeline.coverage_admission_countries a on a.country_id = p.country_id and a.active
     where f.kind = 'english_policy' and f.evidence_id is not null and f.status <> 'rejected' and f.decision is distinct from 'rejected'
       and not exists (select 1 from pipeline.elr_central_reads r where r.fact_source_id = f.id and r.extractor = 'elr-central-v1.0' and r.outcome <> 'lost')
       and not exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = f.provider_id and o.kind = 'english_policy' and o.parser = 'elr-central-v1.0' and o.status in ('proposed', 'approved'))
       and exists (select 1 from catalogue.courses c where c.provider_id = f.provider_id and c.lifecycle_status = 'active'
                    and not exists (select 1 from catalogue.course_english_requirements r where r.course_id = c.id and r.status = 'active'))
     group by f.provider_id order by f.provider_id limit greatest(p_providers, 0))
  select f.id, f.provider_id, f.evidence_id, e.storage_path
    from pv join pipeline.provider_fact_sources f on f.provider_id = pv.provider_id and f.kind = 'english_policy' and f.evidence_id is not null
              and f.status <> 'rejected' and f.decision is distinct from 'rejected'
    join pipeline.evidence_artifacts e on e.id = f.evidence_id and e.storage_path is not null
   order by f.provider_id, f.rank
$f$;
comment on function security.elr_central_claim_v1(integer) is 'CF-247 s885: the stored central English pages of the next universities that still have courses with no English requirement and no elr-central policy. Reads only.';
revoke all on function security.elr_central_claim_v1(integer) from public, anon, authenticated;

-- (s885) the writer: one proposal a university on the governed English policy route, holding only the tiers its approved policy does not give
create or replace function security.elr_central_record_v1(p_pages jsonb, p_run text default null) returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  v_x constant text := 'elr-central-v1.0';
  pv record; pg jsonb; b record; t text; v_tiers text[] := array['undergraduate', 'postgraduate', 'research', 'vet'];
  v_merged jsonb; v_conf jsonb; v_disc jsonb; v_defaults jsonb; v_base_tiers text[]; v_best jsonb; v_best_n int; v_n int; v_id uuid; v_reason text;
  v_read int := 0; v_failed int := 0; v_proposed int := 0; v_none int := 0; v_skipped int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if jsonb_typeof(p_pages) <> 'array' then raise exception 'p_pages must be an array'; end if;
  -- every page first: read or failed
  for pg in select * from jsonb_array_elements(p_pages) loop
    continue when nullif(pg->>'fact_source_id', '') is null;
    insert into pipeline.elr_central_reads as r (fact_source_id, extractor, provider_id, evidence_id, outcome, sha256, reading, result, read_at)
    values ((pg->>'fact_source_id')::uuid, v_x, (pg->>'provider_id')::uuid, nullif(pg->>'evidence_id', '')::uuid, case when pg ? 'error' then 'failed' else 'read' end,
            pg->>'sha256', pg->'reading', case when pg ? 'error' then left(pg->>'error', 160) end, now())
    on conflict (fact_source_id, extractor) do update set outcome = excluded.outcome, sha256 = excluded.sha256, reading = excluded.reading, result = excluded.result, read_at = now();
    if pg ? 'error' then v_failed := v_failed + 1; else v_read := v_read + 1; end if;
  end loop;
  -- then one decision a university
  for pv in select distinct (e->>'provider_id')::uuid provider_id from jsonb_array_elements(p_pages) e where nullif(e->>'provider_id', '') is not null and not (e ? 'error') loop
    v_reason := null;
    if exists (select 1 from pipeline.provider_policy_proposals o where o.provider_id = pv.provider_id and o.kind = 'english_policy' and o.parser = v_x and o.status in ('proposed', 'approved')) then
      v_reason := 'the university already has an elr-central reading';
    end if;
    -- the approved policy in force for the university (not an elr-central one): its tiers are never replaced
    select o.* into b from pipeline.provider_policy_proposals o
     where o.provider_id = pv.provider_id and o.kind = 'english_policy' and o.status = 'approved' and o.parser is distinct from v_x order by o.decided_at desc nulls last limit 1;
    v_base_tiers := coalesce((select array_agg(k) from jsonb_each(coalesce(b.proposal->'defaults', '{}'::jsonb)) d(k, v) where jsonb_typeof(d.v) = 'array' and jsonb_array_length(d.v) > 0), '{}');
    -- merge the university's pages: one value per tier and test, else a conflict
    v_defaults := '{}'::jsonb; v_conf := '[]'::jsonb;
    for t in select unnest(v_tiers) loop
      with q as (
        select r->>'test_code' code, r from jsonb_array_elements(p_pages) e, jsonb_array_elements(case when jsonb_typeof(e->'reading'->'defaults'->t) = 'array' then e->'reading'->'defaults'->t else '[]'::jsonb end) r
         where (e->>'provider_id')::uuid = pv.provider_id and not (e ? 'error')),
      g as (select code, count(distinct (r->>'overall_score')::numeric) nv, (array_agg(r))[1] r1 from q group by code)
      select coalesce(jsonb_agg(g.r1) filter (where g.nv = 1), '[]'::jsonb), coalesce(jsonb_agg(jsonb_build_object('tier', t, 'test_code', g.code)) filter (where g.nv > 1), '[]'::jsonb)
        into v_merged, v_disc from g;
      v_conf := v_conf || v_disc
             || coalesce((select jsonb_agg(c) from jsonb_array_elements(p_pages) e, jsonb_array_elements(coalesce(e->'reading'->'conflicts', '[]'::jsonb)) c
                          where (e->>'provider_id')::uuid = pv.provider_id and c->>'tier' = t), '[]'::jsonb);
      if jsonb_array_length(v_merged) > 0 and not (t = any (v_base_tiers)) then v_defaults := v_defaults || jsonb_build_object(t, v_merged); end if;
    end loop;
    v_disc := coalesce((select jsonb_agg(distinct d) from jsonb_array_elements(p_pages) e, jsonb_array_elements(coalesce(e->'reading'->'discipline_higher', '[]'::jsonb)) d
                         where (e->>'provider_id')::uuid = pv.provider_id), '[]'::jsonb);
    if v_reason is null and v_defaults = '{}'::jsonb then
      v_reason := case when exists (select 1 from jsonb_array_elements(p_pages) e where (e->>'provider_id')::uuid = pv.provider_id and (e->'reading'->>'readings')::int > 0)
                       then 'no tier the approved policy lacks (or every value conflicts)' else 'the page states no English test requirement by tier' end;
    end if;
    if v_reason is not null then
      update pipeline.elr_central_reads r set result = v_reason where r.provider_id = pv.provider_id and r.extractor = v_x and r.outcome = 'read' and r.result is null;
      if v_reason like 'the university already%' then v_skipped := v_skipped + 1; else v_none := v_none + 1; end if;
      continue;
    end if;
    -- the page that gives the most of these tiers is the proposal's document
    v_best := null; v_best_n := -1;
    for pg in select e from jsonb_array_elements(p_pages) e where (e->>'provider_id')::uuid = pv.provider_id and not (e ? 'error') loop
      select count(*) into v_n from jsonb_object_keys(v_defaults) k where jsonb_typeof(pg->'reading'->'defaults'->k) = 'array';
      if v_n > v_best_n then v_best := pg; v_best_n := v_n; end if;
    end loop;
    insert into pipeline.provider_policy_proposals (provider_id, fact_source_id, kind, parser, content_hash, evidence_id, url, style, proposal, status)
    select pv.provider_id, f.id, 'english_policy', v_x, v_best->>'sha256', f.evidence_id, f.url, 'level_default',
           jsonb_build_object('parser', v_x, 'style', 'level_default', 'defaults', v_defaults,
                              'named', coalesce(b.proposal->'named', '[]'::jsonb), 'exceptions', coalesce(b.proposal->'exceptions', '[]'::jsonb),
                              'discipline_higher', v_disc, 'conflicts', v_conf, 'caveats', jsonb_build_array('read_deterministically'), 'signals', '[]'::jsonb,
                              'supplements', b.id, 'run', p_run,
                              'source_note', 'Read deterministically from the stored central English page (no AI, no Firecrawl); only the study-level tiers the approved policy does not already give'),
           'proposed'
      from pipeline.provider_fact_sources f where f.id = (v_best->>'fact_source_id')::uuid
    returning id into v_id;
    update pipeline.elr_central_reads r set proposal_id = v_id, result = 'proposed: ' || (select string_agg(k, ', ') from jsonb_object_keys(v_defaults) k)
     where r.provider_id = pv.provider_id and r.extractor = v_x and r.outcome = 'read' and r.result is null;
    v_proposed := v_proposed + 1;
  end loop;
  return jsonb_build_object('pages_read', v_read, 'pages_failed', v_failed, 'proposed', v_proposed, 'no_new_tier', v_none, 'skipped', v_skipped, 'extractor', v_x);
end $f$;
comment on function security.elr_central_record_v1(jsonb, text) is 'CF-247 s885: records the central English pages the deterministic central reader read, then makes at most one english_policy proposal a university (parser elr-central-v1.0, status proposed) holding only the study-level tiers its approved policy does not give, with that policy''s named courses and exceptions, the conflicts and the regulated disciplines the page gives higher bands for. Approval is the governed route (security.policy_auto_approve_v1 or a person).';
revoke all on function security.elr_central_record_v1(jsonb, text) from public, anon, authenticated;

-- (s886) one run of the sweep: read back answered calls (course pages and central pages), give up lost ones, send the next batches, apply approved central policies
create or replace function security.elr_det_sweep_tick_v1() returns jsonb
language plpgsql security definer set search_path to ''
as $f$
declare
  q record; v_res jsonb; v_rec jsonb; v_harv int := 0; v_bad int := 0; v_lost int := 0; v_sent int := 0; v_pages int := 0;
  v_open int; v_room int; v_batch int; v_per int; v_cur uuid; v_all jsonb; v_items jsonb; v_id bigint; v_claimed int; v_last uuid; i int;
  v_t0 timestamptz := clock_timestamp(); v_c jsonb := '{}'::jsonb; v_cid bigint; v_cpages jsonb; v_capp int := 0; v_cw int := 0; v_cl4 int := 0; ap record; v_ap jsonb; v_l4 int;
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247:elr_det_sweep')) then return jsonb_build_object('skipped', 'another run is working'); end if;  -- fixed: one run at a time
  -- 1. answered calls
  for q in select r.id, r.mode, h.status_code, h.content, h.timed_out, h.error_msg from pipeline.elr_det_requests r join net._http_response h on h.id = r.id where r.status = 'sent' order by r.id loop
    begin v_res := q.content::jsonb; exception when others then v_res := null; end;
    if q.mode = 'elr_central_read' and coalesce(q.timed_out, false) = false and q.status_code between 200 and 299 and v_res->>'ok' = 'true' and v_res->>'extractor' = 'elr-central-v1.0' then
      v_rec := security.elr_central_record_v1(v_res->'pages', 'request:' || q.id);
      update pipeline.elr_det_requests set status = 'done', finished_at = now(), result = v_rec where id = q.id;
      v_harv := v_harv + 1;
    elsif q.mode = 'elr_det_read' and coalesce(q.timed_out, false) = false and q.status_code between 200 and 299 and v_res->>'ok' = 'true' and v_res->>'extractor' = 'elr-det-v1.0' then
      v_rec := security.elr_det_record_v1(v_res->'pages', 'request:' || q.id);
      update pipeline.elr_det_requests set status = 'done', finished_at = now(), result = v_rec where id = q.id;
      v_harv := v_harv + 1;
    else
      update pipeline.elr_det_requests set status = 'failed', finished_at = now(), result = jsonb_build_object('http', q.status_code, 'timed_out', q.timed_out, 'error', left(coalesce(q.error_msg, q.content, ''), 300)) where id = q.id;
      v_bad := v_bad + 1;
    end if;
    update pipeline.elr_det_pages set outcome = 'lost' where request_id = q.id and outcome = 'sent';
    update pipeline.elr_central_reads set outcome = 'lost' where request_id = q.id and outcome = 'sent';
  end loop;
  -- 2. calls with no answer in time are given up; their pages go back to the queue
  with l as (update pipeline.elr_det_requests set status = 'lost', finished_at = now()
              where status = 'sent' and submitted_at < now() - make_interval(mins => security.pipeline_num_v1('elr_det.request_lost_minutes', 30)::int) returning id)
  update pipeline.elr_det_pages d set outcome = 'lost' from l where d.request_id = l.id and d.outcome = 'sent';
  get diagnostics v_lost = row_count;
  update pipeline.elr_central_reads c set outcome = 'lost'
    from pipeline.elr_det_requests l where l.id = c.request_id and l.status = 'lost' and c.outcome = 'sent';
  -- 3. the next batch
  if security.pipeline_num_v1('elr_det.sweep_on', 1) < 1 then
    return jsonb_build_object('read_back', v_harv, 'failed', v_bad, 'pages_lost', v_lost, 'sent', 0, 'sweep', 'off', 'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000));
  end if;
  select count(*) into v_open from pipeline.elr_det_requests where status = 'sent' and mode = 'elr_det_read';
  v_per := greatest(5, least(40, security.pipeline_num_v1('elr_det.pages_per_call', 25)::int));
  v_room := security.pipeline_num_v1('elr_det.in_flight_max', 8)::int - v_open;
  v_batch := least(security.pipeline_num_v1('batch.elr_det_sweep', 200)::int, greatest(v_room, 0) * v_per);
  if v_batch > 0 then
    select s.cursor_id into v_cur from pipeline.elr_det_state s where s.id = 1 for update;
    select coalesce(jsonb_agg(jsonb_build_object('course_id', c.course_id, 'evidence_id', c.evidence_id, 'storage_path', c.storage_path) order by c.course_id), '[]'::jsonb)
      into v_all from security.elr_det_claim_v1(v_cur, v_batch) c;
    v_claimed := jsonb_array_length(v_all);
    v_last := case when v_claimed > 0 then (v_all->(v_claimed - 1)->>'course_id')::uuid end;
    i := 0;
    while i * v_per < v_claimed loop
      select jsonb_agg(e.v order by e.n) into v_items from jsonb_array_elements(v_all) with ordinality e(v, n) where e.n > i * v_per and e.n <= (i + 1) * v_per;
      v_id := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'elr_det_read', 'items', v_items));
      insert into pipeline.elr_det_requests (id, pages) values (v_id, jsonb_array_length(v_items));
      insert into pipeline.elr_det_pages as d (course_id, evidence_id, extractor, outcome, request_id, sent_at)
      select (e->>'course_id')::uuid, (e->>'evidence_id')::uuid, 'elr-det-v1.0', 'sent', v_id, now() from jsonb_array_elements(v_items) e
      on conflict (course_id, evidence_id, extractor) do update set outcome = 'sent', request_id = excluded.request_id, sent_at = now(), result = null where d.outcome = 'lost';
      v_sent := v_sent + 1; v_pages := v_pages + jsonb_array_length(v_items); i := i + 1;
    end loop;
    update pipeline.elr_det_state set cursor_id = case when v_claimed < v_batch then '00000000-0000-0000-0000-000000000000'::uuid else v_last end,
           passes = passes + case when v_claimed < v_batch then 1 else 0 end, updated_at = now() where id = 1;
  end if;
  -- 4. central English pages (s886): one call a run for the next universities, only when none is waiting
  if security.pipeline_num_v1('elr_central.on', 1) >= 1 then
    if not exists (select 1 from pipeline.elr_det_requests where status = 'sent' and mode = 'elr_central_read') then
      select coalesce(jsonb_agg(jsonb_build_object('fact_source_id', c.fact_source_id, 'provider_id', c.provider_id, 'evidence_id', c.evidence_id, 'storage_path', c.storage_path)), '[]'::jsonb)
        into v_cpages from security.elr_central_claim_v1(security.pipeline_num_v1('batch.elr_central', 6)::int) c;
      if jsonb_array_length(v_cpages) > 0 then
        v_cid := pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'elr_central_read', 'items', v_cpages));
        insert into pipeline.elr_det_requests (id, pages, mode) values (v_cid, jsonb_array_length(v_cpages), 'elr_central_read');
        insert into pipeline.elr_central_reads as r (fact_source_id, extractor, provider_id, evidence_id, outcome, request_id, sent_at)
        select (e->>'fact_source_id')::uuid, 'elr-central-v1.0', (e->>'provider_id')::uuid, (e->>'evidence_id')::uuid, 'sent', v_cid, now() from jsonb_array_elements(v_cpages) e
        on conflict (fact_source_id, extractor) do update set outcome = 'sent', request_id = excluded.request_id, sent_at = now(), result = null where r.outcome = 'lost';
        v_c := v_c || jsonb_build_object('central_pages_sent', jsonb_array_length(v_cpages));
      end if;
    end if;
    -- 5. apply approved central policies, a few a run; send their regulated-discipline holds to Layer 4
    for ap in select o.id, o.evidence_id, o.url, o.proposal from pipeline.provider_policy_proposals o left join pipeline.elr_central_applies a on a.proposal_id = o.id
               where o.kind = 'english_policy' and o.status = 'approved' and o.parser = 'elr-central-v1.0'
                 and (a.applied_at is null or a.applied_at < now() - make_interval(hours => security.pipeline_num_v1('elr_central.reapply_hours', 6)::int))
               order by a.applied_at nulls first, o.decided_at limit security.pipeline_num_v1('elr_central.apply_per_run', 2)::int loop
      begin
        v_ap := security.provider_english_apply_v1(ap.id);
        with h as (
          select pl.course_id, substring(pl.reason from '^regulated discipline \(([^)]+)\)') disc
            from security.provider_english_plan_v1(ap.id) pl
           where pl.outcome = 'held' and pl.reason like 'regulated discipline%'
             and not exists (select 1 from catalogue.course_english_requirements r where r.course_id = pl.course_id and r.status = 'active')
             and not exists (select 1 from pipeline.layer4_review_items i where i.entity_id = pl.course_id and i.field_code = 'course_english' and i.status = 'pending')
           limit security.pipeline_num_v1('elr_central.l4_per_run', 50)::int)
        insert into pipeline.layer4_review_items (entity_type, entity_id, field_code, evidence_id, before_value, proposed_value, layer2_state, escalation_reason, change_control_ref)
        select 'course', h.course_id, 'course_english', ap.evidence_id, '{}'::jsonb,
               jsonb_build_object('english_requirements', '[]'::jsonb, 'source', 'elr-central-v1.0', 'policy_id', ap.id,
                                  'central_page_says', (select coalesce(jsonb_agg(d), '[]'::jsonb) from jsonb_array_elements(coalesce(ap.proposal->'discipline_higher', '[]'::jsonb)) d where d->>'discipline' = h.disc)),
               jsonb_build_object('source', 'elr_central', 'policy', ap.id, 'page', ap.url, 'discipline', h.disc),
               'Regulated discipline (' || h.disc || '): the university''s central English page gives higher English bands for these courses, so the general default is not used. Set this course''s requirement from its course or faculty page.',
               'CF-CHG-20260915-247'
          from h;
        get diagnostics v_l4 = row_count;
        insert into pipeline.elr_central_applies as a (proposal_id, applied_at, runs, written, layer4)
        values (ap.id, now(), 1, coalesce((v_ap->>'written')::int, 0), v_l4)
        on conflict (proposal_id) do update set applied_at = now(), runs = a.runs + 1, written = a.written + excluded.written, layer4 = a.layer4 + excluded.layer4, last_error = null;
        v_capp := v_capp + 1; v_cw := v_cw + coalesce((v_ap->>'written')::int, 0); v_cl4 := v_cl4 + v_l4;
      exception when others then
        insert into pipeline.elr_central_applies as a (proposal_id, applied_at, runs, last_error) values (ap.id, now(), 1, left(sqlerrm, 200))
        on conflict (proposal_id) do update set applied_at = now(), runs = a.runs + 1, last_error = excluded.last_error;
      end;
    end loop;
    v_c := v_c || jsonb_build_object('central_applied', v_capp, 'central_written', v_cw, 'central_layer4', v_cl4);
  end if;
  return jsonb_build_object('read_back', v_harv, 'failed', v_bad, 'pages_lost', v_lost, 'calls_sent', v_sent, 'pages_sent', v_pages, 'open_before', v_open,
                            'ms', round(extract(epoch from clock_timestamp() - v_t0) * 1000)) || v_c;
end $f$;
comment on function security.elr_det_sweep_tick_v1() is 'CF-247 s842, s886: one run of the job elr-det-sweep. Also reads stored central English pages (security.elr_central_claim_v1, worker mode elr_central_read, security.elr_central_record_v1), applies approved elr-central policies a few a run and sends their regulated-discipline holds to Layer 4. Reads back the worker''s answers (pg_net) and records them through security.elr_det_record_v1, gives up calls with no answer in time, then sends the next indexed batch of gap course pages to the coverage-sweep worker (mode elr_det_read). $0: no model, no Firecrawl.';
revoke all on function security.elr_det_sweep_tick_v1() from public, anon, authenticated;

-- (s886) what the sweep has done and what is left, course pages and central pages (read only; for the workflow and the reports)
create or replace function security.elr_det_status_v1() returns jsonb
language sql stable security definer set search_path to ''
as $f$
  with ac as (
    select c.id, co.iso_alpha2 cc from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries co on co.id = p.country_id
     where c.lifecycle_status = 'active' and co.iso_alpha2 in ('AU', 'NZ', 'CA')),
  t as (
    select ac.cc, count(*) n,
           count(*) filter (where exists (select 1 from catalogue.course_english_requirements r where r.course_id = ac.id and r.status = 'active')) with_elr,
           count(*) filter (where not exists (select 1 from catalogue.course_english_requirements r where r.course_id = ac.id and r.status = 'active')
                              and exists (select 1 from pipeline.coverage_course_pages g join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
                                           where g.course_id = ac.id and g.status = 'bound')) gap_page,
           count(*) filter (where not exists (select 1 from catalogue.course_english_requirements r where r.course_id = ac.id and r.status = 'active')
                              and not exists (select 1 from pipeline.coverage_course_pages g join pipeline.evidence_artifacts e on e.id = g.evidence_id and e.storage_path is not null
                                               where g.course_id = ac.id and g.status = 'bound')) gap_nopage
      from ac group by 1)
  select jsonb_build_object(
    'by_country', (select jsonb_object_agg(cc, jsonb_build_object('active', n, 'with_elr', with_elr, 'gap_with_page', gap_page, 'gap_no_page', gap_nopage)) from t),
    'pages', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select outcome || ':' || coalesce(split_part(result, ':', 1), '-') k, count(*) n from pipeline.elr_det_pages group by 1) z),
    'readings', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select status || ':' || test_key k, count(*) n from pipeline.elr_det_readings group by 1) z),
    'held_reasons', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select left(coalesce(result, '-'), 60) k, count(*) n from pipeline.elr_det_pages where result like 'held:%' group by 1 order by 2 desc limit 10) z),
    'rows_promoted', (select count(*) from catalogue.course_english_requirements where source_requirement_key like 'elr-det:%' and status = 'active'),
    'courses_promoted', (select count(distinct course_id) from catalogue.course_english_requirements where source_requirement_key like 'elr-det:%' and status = 'active'),
    'layer4_pending', (select count(*) from pipeline.layer4_review_items where field_code = 'course_english' and status = 'pending' and layer2_state->>'source' = 'elr_det'),
    'calls', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from pipeline.elr_det_requests group by 1) z),
    'state', (select to_jsonb(s) from pipeline.elr_det_state s where s.id = 1),
    'manual_locks', (select count(*) from pipeline.manual_locks),
    'central', jsonb_build_object(
      'pages', (select coalesce(jsonb_object_agg(k, n), '{}'::jsonb) from (select outcome || ':' || coalesce(split_part(result, ':', 1), '-') k, count(*) n from pipeline.elr_central_reads group by 1) z),
      'policies', (select coalesce(jsonb_object_agg(status, n), '{}'::jsonb) from (select status, count(*) n from pipeline.provider_policy_proposals where kind = 'english_policy' and parser = 'elr-central-v1.0' group by 1) z),
      'applied', (select coalesce(jsonb_build_object('policies', count(*), 'written', sum(written), 'layer4', sum(layer4), 'errors', count(*) filter (where last_error is not null)), '{}'::jsonb) from pipeline.elr_central_applies),
      'rows_active', (select count(*) from catalogue.course_english_requirements r join pipeline.provider_policy_proposals o on r.source_requirement_key like 'policy:' || o.id || ':%'
                       where o.parser = 'elr-central-v1.0' and r.status = 'active'),
      'layer4_pending', (select count(*) from pipeline.layer4_review_items where field_code = 'course_english' and status = 'pending' and layer2_state->>'source' = 'elr_central')))
$f$;
comment on function security.elr_det_status_v1() is 'CF-247 s842, s886: English requirement coverage of active AU, NZ and CA courses (with a requirement, gap with a stored page, gap without) and what the sweep has read, promoted, sent to Layer 4 and held. Reads only.';
revoke all on function security.elr_det_status_v1() from public, anon, authenticated;

-- (G1) no new job: the existing elr-det-sweep line says what it now does
update pipeline.automation_catalogue
   set description = 'Every 5 minutes: reads back the answers of its earlier calls and records them, then sends the next batch of stored course pages of courses with no English requirement to the deterministic English reader (no AI, no Firecrawl). It also reads the stored central English pages of universities that still have such courses (elr-central), proposes the study-level tiers their approved policy lacks on the governed policy route, applies approved central policies a few a run, and sends regulated-discipline courses to Layer 4. Readings never overwrite an existing requirement or a manual lock. Switch off with English requirement sweep: on, or the central part with English requirement sweep: read central English pages.'
 where jobname = 'elr-det-sweep';

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in) values
  ('table', 'pipeline.elr_central_reads', 'Layer 2', 'English requirements', 'Central English pages the deterministic central reader was sent or has read, with the outcome', 'active', '{}', '20261120220000'),
  ('table', 'pipeline.elr_central_applies', 'Layer 2', 'English requirements', 'When each approved elr-central policy was last applied by the sweep', 'active', '{}', '20261120220000'),
  ('function', 'security.elr_central_claim_v1', 'Layer 2', 'English requirements', 'Next universities with stored central English pages to read', 'active', '{}', '20261120220000'),
  ('function', 'security.elr_central_record_v1', 'Layer 2', 'English requirements', 'Turns central-page readings into a governed English policy proposal (missing tiers only)', 'active', '{}', '20261120220000')
on conflict do nothing;

-- post-checks
do $c$
declare r record; v_h text; v_api jsonb; t0 timestamptz; v_ms numeric; v_n int;
begin
  -- the existing approved policies' plans are unchanged (they state no VET tier and no regulated-discipline reading)
  for r in select * from s885_plan_before loop
    select md5(coalesce(string_agg(t::text, '|' order by t.course_id), '')) into v_h from security.provider_english_plan_v1(r.proposal_id) t;
    if v_h <> r.h then raise exception 'post-check: the English plan of proposal % changed', r.proposal_id; end if;
  end loop;
  t0 := clock_timestamp();
  select count(*) into v_n from security.elr_central_claim_v1(15);
  v_ms := extract(epoch from clock_timestamp() - t0) * 1000;
  if v_n = 0 then raise exception 'post-check: the central claim found no page (expected the stored central pages of universities with Table 1 courses)'; end if;
  if (security.elr_central_record_v1('[]'::jsonb, 'post-check')->>'proposed')::int <> 0 then raise exception 'post-check: the central writer answered an empty call wrongly'; end if;
  if (select count(*) from cron.job where active) <> (select n from s885_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s885_locks) then raise exception 'post-check: the manual locks changed'; end if;
  if (select count(*) from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key in ('elr_central.on', 'batch.elr_central', 'elr_central.apply_per_run',
        'elr_central.reapply_hours', 'elr_central.l4_per_run', 'central.auto_approve_elr_central')) <> 6 then raise exception 'post-check: a setting is missing (G2)'; end if;
  if position('elr-central-v1.0' in pg_get_functiondef('security.policy_auto_approve_v1()'::regprocedure)) = 0
     or position('elr-central-v1.0' in pg_get_functiondef('security.provider_english_apply_all_v1()'::regprocedure)) = 0 then
    raise exception 'post-check: the approval or apply-all change is missing';
  end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  raise notice 's885: central claim % ms for % pages', round(v_ms), v_n;
end $c$;
