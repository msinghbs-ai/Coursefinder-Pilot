-- CF-247 scholarship course links: the person's decision also governs the automated sweep (1 Oct 2026).
-- Found while testing: 17,008 of the 37,200 waiting links were already mapped by the automated scholarship sweep
-- (basis sweep_level_field_scope), for example the "Master of Global Medicines Development Pioneers Scholarship" was
-- mapped to 25 Monash courses when it is for one course. A decision now:
--   - takes over matching sweep mappings (basis becomes scope_decision:<decision>, so the sweep no longer removes them);
--   - removes sweep mappings for this scholarship's courses that do not match the decision;
--   - and a guard trigger stops the sweep adding a mapping the decision excludes.
-- Mappings from the scholarship's own stated scope (explicit_provider_scope) and other human bases are untouched.
-- md5-guarded replacement of security.scholarship_scope_apply_v1.
do $$
begin
  if (select md5(prosrc) from pg_proc where oid = 'security.scholarship_scope_apply_v1(uuid,uuid)'::regprocedure) <> '714ab7f0d99c5657cd083a8bbb5f3403' then
    raise exception 'scholarship_scope_apply_v1 changed; review first';
  end if;
end $$;

create or replace function security.scholarship_scope_apply_v1(p_scholarship_id uuid, p_actor uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
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
end $$;
revoke all on function security.scholarship_scope_apply_v1(uuid, uuid) from public, anon, authenticated;

create or replace function security.scholarship_mapping_decision_guard() returns trigger language plpgsql security definer set search_path = '' as $$
declare d pipeline.scholarship_scope_decisions%rowtype;
begin
  if NEW.mapping_basis is distinct from 'sweep_level_field_scope' then return NEW; end if;
  select * into d from pipeline.scholarship_scope_decisions where scholarship_id = NEW.scholarship_id;
  if d.scholarship_id is not null and not security.scholarship_scope_match(NEW.course_id, d.decision, d.filter) then return null; end if;
  return NEW;
end $$;
revoke all on function security.scholarship_mapping_decision_guard() from public, anon, authenticated;
drop trigger if exists scholarship_decision_guard on scholarship.course_mappings;
create trigger scholarship_decision_guard before insert or update on scholarship.course_mappings for each row execute function security.scholarship_mapping_decision_guard();
