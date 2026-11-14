-- Rows loaded into both databases (as live, and migrated) before the migration runs, so the readers are compared on the same rows.
insert into auth.users values ('00000000-0000-0000-0000-0000000000a1', 'admin@example.test');
insert into ref.countries values (1, 'Australia', 'AU');
insert into ref.study_levels values (1, 'Bachelor', 'bachelor', 1);
insert into ref.fields_of_study values ('asced-0201', 'Computer Science');
insert into catalogue.providers values ('00000000-0000-0000-0000-00000000b001', 'Fixture University', 'Fixture University', 'https://fixture.example', 1);
insert into catalogue.courses values ('00000000-0000-0000-0000-00000000c001', 'Bachelor of Fixtures', 1), ('00000000-0000-0000-0000-00000000c002', 'Bachelor of Tests', 1);
insert into pipeline.admin_jobs values ('00000000-0000-0000-0000-00000000d001', '{}');
insert into pipeline.field_enrich_items (job_id, provider_id, course_id, field, state, source, storage_path) values
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000c001', 'description', 'ai', 'ai_stored', 'p/c1.md'),
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000c001', 'entry_requirements', 'ai', 'ai_stored', 'p/c1.md'),
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000c001', 'deadline', 'ai', 'ai_stored', 'p/c1.md'),
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000c002', 'description', 'ai', 'ai_stored', 'p/c2.md'),
  ('00000000-0000-0000-0000-00000000d001', '00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000c002', 'intakes', 'ai', 'ai_stored', 'p/c2.md');
insert into pipeline.evidence_artifacts values ('00000000-0000-0000-0000-00000000e001', 'm/matrix.html', 'text/html');
insert into pipeline.entry_matrix_sources values ('00000000-0000-0000-0000-00000000f001', 'https://fixture.example/entry', '00000000-0000-0000-0000-00000000e001');
insert into pipeline.entry_matrix_runs (id, provider_id, source_id, state) values ('00000000-0000-0000-0000-000000001001', '00000000-0000-0000-0000-00000000b001', '00000000-0000-0000-0000-00000000f001', 'queued');
insert into pipeline.ops_ai_diagnosis_requests (issue_id, state, context) values (1, 'queued', '{"root_causes": ["unknown"]}');
insert into pipeline.central_ai_queue (provider_id, kind, state) values ('00000000-0000-0000-0000-00000000b001', 'intake_calendar', 'queued'), ('00000000-0000-0000-0000-00000000b001', 'english_policy', 'queued');
insert into pipeline.layer3_openrouter_observations (kind, payload, remaining_usd) values ('credits', '{"total_credits": 100, "total_usage": 47}', 53);
-- costs recorded before the migration (no service, no model): two course fields, a scholarship page, a calendar
insert into pipeline.ai_spend_ledger (lane, source, source_id, cost_usd) values
  ('enrich_fields', 'field_enrich_items', '1', 0.20), ('enrich_fields', 'field_enrich_items', '2', 0.30), ('enrich_fields', 'field_enrich_items', '3', 0.01),
  ('scholarship_ai', 'scholarship_ai_extractions', '77', 0.05), ('scholarship_ai', 'scholarship_eligibility_reads', '78', 0.02),
  ('central_ai', 'central_ai_queue', '1', 0.04), ('entry_matrix', 'aer_v2_shadow_results', '5', 0.03), ('course_match', 'opening', null, 0.01);
-- the shape of a json value: every key path with its type (the first element stands for an array), to compare a reader before and after
create function public.fx_shape(j jsonb, p text default '') returns setof text language plpgsql as $$
declare k text; v jsonb;
begin
  if jsonb_typeof(j) = 'object' then
    for k, v in select * from jsonb_each(j) loop
      return next p || '.' || k || ':' || jsonb_typeof(v);
      return query select * from public.fx_shape(v, p || '.' || k);
    end loop;
  elsif jsonb_typeof(j) = 'array' and jsonb_array_length(j) > 0 then
    return query select * from public.fx_shape(j->0, p || '[]');
  end if;
end $$;
-- the operations diagnosis reader only leases when its lane is counted by security.ai_spend_today_v1; live does not list it yet (the reader is
-- held on live for that reason, before and after this change). The fixture adds the lane in both databases so the lease path can be compared.
create or replace function security.ai_spend_today_v1() returns table(use text, label text, spent numeric, guard numeric, calls bigint) language sql stable as $$
  select l.u, l.u, coalesce((select sum(x.cost_usd) from pipeline.ai_spend_ledger x where x.lane = l.u and x.at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC')), 0), null::numeric, 0::bigint
    from (values ('enrich_fields'), ('entry_matrix'), ('ops_diagnose'), ('central_ai'), ('scholarship_ai'), ('course_match')) l(u)
$$;
