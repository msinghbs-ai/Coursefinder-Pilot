CREATE OR REPLACE FUNCTION security.layer4_provider_departure_decide_v1(p_id bigint, p_decision text, p_successor_provider_id uuid, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'security', 'pipeline', 'catalogue'
AS $function$
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
end $function$
