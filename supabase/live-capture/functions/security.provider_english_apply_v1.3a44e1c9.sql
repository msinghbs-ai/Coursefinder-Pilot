CREATE OR REPLACE FUNCTION security.provider_english_apply_v1(p_proposal_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'catalogue', 'pipeline', 'security', 'search'
AS $function$
declare x pipeline.provider_policy_proposals%rowtype; v_src uuid; v_name text; r record; v_ok int := 0; v_err int := 0; v_courses uuid[] := '{}'; v_last text;
  v_flag boolean; v_flagged int := 0;
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
  -- courses open to international students first
  for r in select pl.* from security.provider_english_plan_v1(p_proposal_id) pl join catalogue.courses co on co.id = pl.course_id
            where pl.outcome = 'write' order by co.open_to_international desc nulls last, pl.title loop
    begin
      perform security.coverage_apply_course_v1(r.course_id, v_src, x.evidence_id, x.url, x.content_hash,
        jsonb_build_object('english_requirements', (select jsonb_agg(jsonb_build_object(
            'test_code', q->>'test_code', 'overall_score', q->'overall_score', 'component_scores', coalesce(q->'component_scores', '{}'::jsonb),
            'source_requirement_key', 'policy:' || x.id || ':' || lower(q->>'test_code'),
            'notes', case when r.plan = 'named' then 'From ' || v_name || '''s English language policy, which names this course (approved by a Platform Admin, Decision 227)'
                          else 'Default for ' || case when r.study_level in ('graduate_certificate', 'graduate_diploma', 'masters', 'masters_coursework', 'masters_extended') then 'postgraduate coursework' else 'undergraduate' end
                               || ' courses in ' || v_name || '''s English language policy (approved by a Platform Admin, Decision 227)'
                               || case when v_flag then '. Flagged: this is the university standard; the policy says some courses need more and does not list them, so check the course page' else '' end end))
          from jsonb_array_elements(r.requirements) q where q->>'test_code' in (select code from ref.english_tests))));
      if v_flag and r.plan <> 'named' then
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
