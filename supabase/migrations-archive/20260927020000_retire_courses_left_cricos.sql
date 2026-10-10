-- CF-247 / Decision 155: retire AU courses no longer in the CRICOS register (26 Sep 2026 catch-up)
create table if not exists pipeline.layer1_course_retirements(
  id bigint generated always as identity primary key,
  course_id uuid not null references catalogue.courses(id),
  provider_id uuid, previous_status text not null, reason text not null,
  evidence_id uuid references pipeline.evidence_artifacts(id), run_id uuid,
  successor_provider_id uuid references catalogue.providers(id),
  retired_at timestamptz not null default now(), reactivated_at timestamptz);
create index if not exists layer1_course_retirements_course_idx on pipeline.layer1_course_retirements(course_id);
alter table pipeline.layer1_course_retirements enable row level security;
revoke all on pipeline.layer1_course_retirements from public, anon, authenticated;
do $retire$
declare v_ids uuid[]; n int; v_before jsonb; v_after jsonb; v_diff jsonb;
  v_evidence constant uuid := 'e86767c8-0644-4abf-916b-01b0f2c73805';
  v_run constant uuid := '5c131b4d-294e-490b-88f6-ab7fc34bee2f';
  v_successor constant uuid := 'de2201a1-69ee-40ff-b6aa-0e54e535e6c0';
begin
  select array_agg(c.id) into v_ids from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries rc on rc.id=p.country_id
  where rc.iso_alpha2='AU' and c.lifecycle_status='active' and (c.last_verified_at < '2026-09-26 13:00+00' or c.last_verified_at is null);
  n := coalesce(cardinality(v_ids),0);
  if n <> 809 then raise exception 'expected 809 courses to retire, found %; aborting', n; end if;
  v_before := security.consumer_api_snapshot_v1();
  insert into pipeline.layer1_course_retirements(course_id,provider_id,previous_status,reason,evidence_id,run_id,successor_provider_id)
  select c.id, c.provider_id, c.lifecycle_status,
    case when c.provider_id in ('73c4ae05-4b36-4175-ac30-31fe1c7b6335','99a4e951-3320-4751-8805-115debb300bd')
         then 'Not in the CRICOS register as of 26 Sep 2026; provider merged into Adelaide University'
         else 'Not in the CRICOS register as of 26 Sep 2026' end,
    v_evidence, v_run,
    case when c.provider_id in ('73c4ae05-4b36-4175-ac30-31fe1c7b6335','99a4e951-3320-4751-8805-115debb300bd') then v_successor end
  from catalogue.courses c where c.id = any(v_ids);
  update catalogue.courses set lifecycle_status='inactive', updated_at=now() where id = any(v_ids) and lifecycle_status='active';
  get diagnostics n = row_count;
  if n <> 809 then raise exception 'updated % courses, expected 809; aborting', n; end if;
  update catalogue.course_registrations set status='inactive' where course_id = any(v_ids) and lower(scheme)='cricos' and status='active';
  insert into search.refresh_requests(requested_by) values ('retire 809 courses that left CRICOS (27 Sep 2026)');
  v_after := security.consumer_api_snapshot_v1();
  v_diff := security.consumer_api_compare_v1(v_before, v_after);
  insert into pipeline.consumer_api_baselines(label, snapshot) values ('before retiring 809 CRICOS departures', v_before), ('after retiring 809 CRICOS departures', v_after);
  raise notice 'retired 809; consumer cases changed immediately: %', jsonb_array_length(v_diff);
end $retire$;
