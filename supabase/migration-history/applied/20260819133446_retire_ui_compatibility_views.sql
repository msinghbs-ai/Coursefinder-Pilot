-- M1-PIM-HARDENING: browser no longer uses compatibility views.
do $$
declare r record;
begin
  for r in
    select c.oid::regclass as rel
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='v'
      and c.relname in ('catalogue_stats','providers','course_completeness_v2','scholarship_catalogue_v2','ingest_jobs','review_queue','evidence_artifacts','pim_attribute_definitions','field_values')
  loop
    execute format('revoke all on %s from public, anon, authenticated',r.rel);
    execute format('grant select on %s to service_role',r.rel);
  end loop;
end$$;
