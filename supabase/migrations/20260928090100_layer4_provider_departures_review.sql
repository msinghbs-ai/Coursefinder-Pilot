-- CF-247 / R25 (Decision 158): review list for providers whose every active course left the register.
-- A person decides each one: closed, merged into a successor, or reviewed (no change). Closed and merged
-- providers are marked inactive (never deleted); a merger records a 'merged_into' provider association.
-- The successor is chosen by a person, never guessed; a successor suggested by an earlier retirement
-- record is shown as a suggestion only. Reading needs Pipeline Operator (rank 4); deciding needs
-- Platform Admin (rank 6) and a reason. Consumer API: the consumer snapshot is recorded before and after
-- every decision that changes a provider.

create or replace function security.layer4_provider_departures_read_v1(p_status text default 'needs_review')
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog','security','pipeline','catalogue','ref' as $f$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank()<4 then raise exception 'Pipeline Operator role required' using errcode='42501'; end if;
  return coalesce((select jsonb_agg(x order by x->>'created_at' desc) from (
    select jsonb_build_object(
      'id',d.id,'provider_id',d.provider_id,'provider_name',coalesce(p.display_name,p.canonical_name),'country_code',co.iso_alpha2,
      'provider_status',p.lifecycle_status,'courses_retired',d.courses_retired,'status',d.status,'note',d.note,'run_id',d.run_id,
      'created_at',d.created_at,'reviewed_at',d.reviewed_at,'successor_provider_id',d.successor_provider_id,
      'successor_name',(select coalesce(s.display_name,s.canonical_name) from catalogue.providers s where s.id=d.successor_provider_id),
      'suggested_successor',(select jsonb_build_object('provider_id',s.id,'name',coalesce(s.display_name,s.canonical_name),'courses',count(*))
          from pipeline.layer1_course_retirements r join catalogue.providers s on s.id=r.successor_provider_id
         where r.provider_id=d.provider_id and r.successor_provider_id is not null group by s.id, s.display_name, s.canonical_name order by count(*) desc limit 1),
      'registrations',(select coalesce(jsonb_agg(jsonb_build_object('scheme',pr.registration_scheme,'code',pr.registration_code,'status',pr.status)),'[]'::jsonb)
          from catalogue.provider_registrations pr where pr.provider_id=d.provider_id),
      'active_courses',(select count(*) from catalogue.courses c where c.provider_id=d.provider_id and c.lifecycle_status='active')) x
    from pipeline.layer1_provider_departures d
    join catalogue.providers p on p.id=d.provider_id
    left join ref.countries co on co.id=p.country_id
    where p_status is null or p_status='all' or d.status=p_status) z),'[]'::jsonb);
end $f$;
revoke all on function security.layer4_provider_departures_read_v1(text) from public, anon;
grant execute on function security.layer4_provider_departures_read_v1(text) to authenticated;

create or replace function public.layer4_provider_departures_read(p_status text default 'needs_review')
returns jsonb language sql stable set search_path to 'pg_catalog','security' as $f$ select security.layer4_provider_departures_read_v1(p_status) $f$;
revoke all on function public.layer4_provider_departures_read(text) from public, anon;
grant execute on function public.layer4_provider_departures_read(text) to authenticated;

create or replace function security.layer4_provider_departure_decide_v1(p_id bigint, p_decision text, p_successor_provider_id uuid, p_reason text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','security','pipeline','catalogue' as $f$
declare d pipeline.layer1_provider_departures; p catalogue.providers; s catalogue.providers; v_before jsonb; v_after jsonb; v_changed boolean:=false;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if security.current_role_rank()<6 then raise exception 'Platform Admin role required' using errcode='42501'; end if;
  if p_decision not in ('closed','merged','reviewed') then raise exception 'decision must be closed, merged or reviewed' using errcode='22023'; end if;
  if length(btrim(coalesce(p_reason,'')))<8 then raise exception 'a reason of at least 8 characters is required' using errcode='22023'; end if;
  select * into d from pipeline.layer1_provider_departures where id=p_id for update;
  if not found then raise exception 'departure not found' using errcode='22023'; end if;
  if d.status<>'needs_review' then raise exception 'this departure was already decided (%)', d.status using errcode='55000'; end if;
  select * into p from catalogue.providers where id=d.provider_id for update;
  if exists (select 1 from catalogue.courses c where c.provider_id=p.id and c.lifecycle_status='active') and p_decision<>'reviewed' then
    raise exception 'the provider has active courses again; choose reviewed' using errcode='55000'; end if;
  if p_decision='merged' then
    if p_successor_provider_id is null then raise exception 'a merger needs a successor provider' using errcode='22023'; end if;
    select * into s from catalogue.providers where id=p_successor_provider_id;
    if not found or s.id=p.id then raise exception 'successor provider not valid' using errcode='22023'; end if;
    if s.country_id is distinct from p.country_id then raise exception 'successor must be in the same country' using errcode='22023'; end if;
    if s.lifecycle_status<>'active' then raise exception 'successor provider is not active' using errcode='22023'; end if;
  elsif p_successor_provider_id is not null then
    raise exception 'a successor is only recorded for a merger' using errcode='22023';
  end if;

  if p_decision in ('closed','merged') and p.lifecycle_status='active' then
    v_before:=security.consumer_api_snapshot_v1();
    update catalogue.providers set lifecycle_status='inactive', updated_at=now() where id=p.id;
    v_changed:=true;
  end if;
  if p_decision='merged' then
    insert into catalogue.provider_associations(from_provider_id,to_provider_id,association_type,valid_from,status,notes)
    values(p.id, s.id, 'merged_into', current_date, 'active', left('Recorded on provider departure review: '||btrim(p_reason),500));
  end if;
  update pipeline.layer1_provider_departures set status=p_decision, successor_provider_id=p_successor_provider_id,
         note=left(coalesce(note,'')||' | Decision: '||btrim(p_reason),1000), reviewed_by=auth.uid(), reviewed_at=now()
   where id=p_id;
  if v_changed then
    v_after:=security.consumer_api_snapshot_v1();
    insert into pipeline.consumer_api_baselines(label, snapshot) values
      (format('before provider departure decision %s (%s)', p_id, p_decision), v_before),
      (format('after provider departure decision %s (%s)', p_id, p_decision), v_after);
    insert into search.refresh_requests(requested_by) values (format('provider departure %s: %s', p_id, p_decision));
  end if;
  return jsonb_build_object('id',p_id,'decision',p_decision,'provider_id',p.id,'provider_inactive',v_changed,'successor_provider_id',p_successor_provider_id);
end $f$;
revoke all on function security.layer4_provider_departure_decide_v1(bigint,text,uuid,text) from public, anon;
grant execute on function security.layer4_provider_departure_decide_v1(bigint,text,uuid,text) to authenticated;

create or replace function public.layer4_provider_departure_decide(p_id bigint, p_decision text, p_successor_provider_id uuid, p_reason text)
returns jsonb language sql set search_path to 'pg_catalog','security' as $f$ select security.layer4_provider_departure_decide_v1(p_id,p_decision,p_successor_provider_id,p_reason) $f$;
revoke all on function public.layer4_provider_departure_decide(bigint,text,uuid,text) from public, anon;
grant execute on function public.layer4_provider_departure_decide(bigint,text,uuid,text) to authenticated;

-- Seed the list with AU/NZ providers that already have no active course (the 26 Sep hand retirement
-- happened before the automatic list existed). Idempotent: one open review per provider.
insert into pipeline.layer1_provider_departures(provider_id,run_id,courses_retired,note)
select p.id, null,
       (select count(*) from catalogue.courses c where c.provider_id=p.id and c.lifecycle_status<>'active'),
       'All registered courses have left the register (before the automatic review list existed); review as a closure or a merger and record any successor.'
  from catalogue.providers p join ref.countries co on co.id=p.country_id
 where co.iso_alpha2 in ('AU','NZ') and p.lifecycle_status='active'
   and exists (select 1 from catalogue.courses c where c.provider_id=p.id)
   and not exists (select 1 from catalogue.courses c where c.provider_id=p.id and c.lifecycle_status='active')
   and not exists (select 1 from pipeline.layer1_provider_departures d where d.provider_id=p.id and d.status='needs_review');
