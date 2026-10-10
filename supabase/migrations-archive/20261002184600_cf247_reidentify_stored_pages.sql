-- CF-247 (2 Oct 2026). Identity rule v0.5.7 (coverage-sweep extract.ts): a page heading that puts the national
-- qualification code before the exact course title ("CHC52025 Diploma of Community Services") is the exact title.
-- Pages already stored and marked as identity mismatches are checked again from their stored copy (no fetch, no
-- credit) by coverage-sweep mode reidentify. A page that now passes is set back to read and bound, so the usual
-- admission runs on it; a page that still fails is left as it is. Pages entered by hand are not touched.
create table if not exists pipeline.coverage_reidentify_done (
  course_id uuid not null,
  evidence_id uuid not null,
  rule text not null,
  identity_basis text,
  checked_at timestamptz not null default now(),
  primary key (course_id, evidence_id, rule)
);
alter table pipeline.coverage_reidentify_done enable row level security;
revoke all on pipeline.coverage_reidentify_done from public, anon, authenticated;

create or replace function public.svc_coverage_reidentify_next(p_limit int, p_rule text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'catalogue', 'pipeline', 'security' as $f$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select coalesce(jsonb_agg(x), '[]'::jsonb) into v from (
    select p.course_id, p.evidence_id, e.storage_path, coalesce(nullif(p.candidates->>'final_url', ''), p.url) url, co.canonical_title title, co.course_code code,
           security.coverage_country(p.provider_id) country
      from pipeline.coverage_course_pages p
      join pipeline.evidence_artifacts e on e.id = p.evidence_id
      join catalogue.courses co on co.id = p.course_id and co.lifecycle_status = 'active'
     where p.status = 'mismatch' and p.read_status = 'identity_mismatch' and coalesce(p.basis, '') <> 'manual' and e.storage_path is not null
       and not exists (select 1 from pipeline.coverage_reidentify_done d where d.course_id = p.course_id and d.evidence_id = p.evidence_id and d.rule = p_rule)
     order by p.course_id limit greatest(1, least(coalesce(p_limit, 100), 400)) for update of p skip locked) x;
  return v;
end $f$;
revoke all on function public.svc_coverage_reidentify_next(int, text) from public, anon, authenticated;
grant execute on function public.svc_coverage_reidentify_next(int, text) to service_role;

create or replace function public.svc_coverage_reidentify_record(p_course_id uuid, p_evidence_id uuid, p_rule text, p_identity_basis text, p_candidates jsonb)
returns text language plpgsql security definer set search_path to 'pg_catalog', 'pipeline' as $f$
declare v_n int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  insert into pipeline.coverage_reidentify_done(course_id, evidence_id, rule, identity_basis) values (p_course_id, p_evidence_id, p_rule, p_identity_basis)
  on conflict (course_id, evidence_id, rule) do nothing;
  if p_identity_basis is not null then
    update pipeline.coverage_course_pages set status = 'bound', read_status = 'read', identity_basis = p_identity_basis, candidates = p_candidates, leased_until = null
     where course_id = p_course_id and evidence_id = p_evidence_id and status = 'mismatch' and coalesce(basis, '') <> 'manual';
    get diagnostics v_n = row_count;
  end if;
  return case when v_n > 0 then 'passed' when p_identity_basis is not null then 'changed' else 'still_mismatch' end;
end $f$;
revoke all on function public.svc_coverage_reidentify_record(uuid, uuid, text, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_coverage_reidentify_record(uuid, uuid, text, text, jsonb) to service_role;
