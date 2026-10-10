-- CF-247, 8 Oct 2026: register files are kept out of the Unreferenced evidence purge. The first purge removed one of two CRICOS archives
-- captured on 11 Aug 2026 (and three extracted Institutions files) because no record pointed to them; three CRICOS archives remain and
-- are the inputs of the Phase 2 side-by-side replay. Register archives and the files extracted from them (storage paths under
-- regulatory/) are now never candidates. Replaces security.retention_evidence_candidates_v1 (migration 1200) behind an md5 guard.
do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'security.retention_evidence_candidates_v1()'::regprocedure) is distinct from '538c6e9daf0fe99540cbbee6f935da0e' then
    raise exception 'retention_evidence_candidates_v1 is not the migration 1200 definition; refusing to replace it';
  end if;
end $g$;
create or replace function security.retention_evidence_candidates_v1()
returns table(evidence_id uuid, storage_path text, created_at timestamptz) language sql stable security definer set search_path to '' as $f$
  with a as (select r.started_at from pipeline.retention_runs r where r.category = 'evidence_audit' and r.status = 'done' order by r.finished_at desc limit 1)
  select e.id, e.storage_path, e.created_at
    from pipeline.evidence_artifacts e, a
   where e.created_at < least(a.started_at, now() - interval '7 days')
     and coalesce(e.retention_class, '') not in ('standard_365', 'source_evidence')
     and coalesce(e.storage_path, '') not like 'regulatory/%'
     and not exists (select 1 from pipeline.evidence_audit_refs r where r.evidence_id = e.id)
$f$;
revoke all on function security.retention_evidence_candidates_v1() from public, anon, authenticated;
