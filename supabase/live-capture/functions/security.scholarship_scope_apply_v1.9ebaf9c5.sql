CREATE OR REPLACE FUNCTION security.scholarship_scope_apply_v1(p_scholarship_id uuid, p_actor uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d pipeline.scholarship_scope_decisions%rowtype; n_acc int := 0; n_rej int := 0; n_removed int := 0; n_sweep int := 0;
begin
  select * into d from pipeline.scholarship_scope_decisions where scholarship_id = p_scholarship_id;
  if d.scholarship_id is null then return jsonb_build_object('applied', false); end if;
  create temp table if not exists pg_temp._ssa(candidate_id uuid, course_id uuid, evidence_id uuid, status text, ok boolean) on commit drop;
  truncate pg_temp._ssa;
  insert into pg_temp._ssa select c.id, c.course_id, c.evidence_id, c.status, security.scholarship_scope_match(c.course_id, d.decision, d.filter)
    from scholarship.course_mapping_candidates c join catalogue.courses co on co.id = c.course_id
    join scholarship.scholarships s on s.id = c.scholarship_id
   where c.scholarship_id = p_scholarship_id and co.provider_id = s.provider_id;
  insert into scholarship.course_mappings(scholarship_id, course_id, mapping_state, mapping_basis, evidence_id, mapped_by)
  select p_scholarship_id, x.course_id, 'mapped', 'scope_decision:' || d.decision, x.evidence_id, p_actor from pg_temp._ssa x where x.ok
  on conflict (scholarship_id, course_id) do update set mapping_basis = excluded.mapping_basis, mapping_state = 'mapped', mapped_by = excluded.mapped_by, updated_at = now()
   where scholarship.course_mappings.mapping_basis in ('sweep_level_field_scope') or scholarship.course_mappings.mapping_basis like 'scope_decision:%';
  delete from scholarship.course_mappings m using pg_temp._ssa x
   where m.scholarship_id = p_scholarship_id and m.course_id = x.course_id and not x.ok and m.mapping_basis like 'scope_decision:%';
  get diagnostics n_removed = row_count;
  delete from scholarship.course_mappings m
   where m.scholarship_id = p_scholarship_id and m.mapping_basis = 'sweep_level_field_scope'
     and not security.scholarship_scope_match(m.course_id, d.decision, d.filter);
  get diagnostics n_sweep = row_count;
  update scholarship.course_mapping_candidates c set status = case when x.ok then 'accepted' else 'rejected' end, updated_at = now()
    from pg_temp._ssa x where c.id = x.candidate_id and c.status is distinct from case when x.ok then 'accepted' else 'rejected' end;
  select count(*) filter (where ok), count(*) filter (where not ok) into n_acc, n_rej from pg_temp._ssa;
  update pipeline.scholarship_scope_decisions set accepted = n_acc, rejected = n_rej, last_applied_at = now() where scholarship_id = p_scholarship_id;
  return jsonb_build_object('applied', true, 'accepted', n_acc, 'rejected', n_rej, 'removed', n_removed, 'sweep_removed', n_sweep);
end $function$
