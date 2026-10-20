CREATE OR REPLACE FUNCTION public.admin_scholarship_layer_write(p_action text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_set pipeline.scholarship_layer_settings%rowtype;
        v_num numeric; v_job bigint; v_cc text; v_role text; v_url text; v_id uuid; v_before jsonb; v_after jsonb; v_target text;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if p_action = 'setting' then
    select * into v_set from pipeline.scholarship_layer_settings where key = p_args->>'key';
    if v_set.key is null then raise exception 'unknown setting'; end if;
    if coalesce(p_args->>'value', '') !~ '^[0-9]+(\.[0-9]+)?$' then raise exception 'enter a number'; end if;
    v_num := (p_args->>'value')::numeric;
    if v_num < v_set.min_value or v_num > v_set.max_value then raise exception 'enter a value from % to %', v_set.min_value, v_set.max_value; end if;
    v_before := to_jsonb(v_set.value); v_after := to_jsonb(v_num); v_target := v_set.label;
    update pipeline.scholarship_layer_settings set value = v_num, updated_at = now(), updated_by = auth.uid(), reason = v_reason where key = v_set.key;
  elsif p_action = 'job' then
    if not exists (select 1 from pipeline.scholarship_jobs j where j.jobname = p_args->>'jobname') then raise exception 'unknown job'; end if;
    select jobid, to_jsonb(active) into v_job, v_before from cron.job where jobname = p_args->>'jobname';
    if v_job is null then raise exception 'the job is not scheduled'; end if;
    perform cron.alter_job(v_job, active := (p_args->>'active')::boolean);
    v_after := to_jsonb((p_args->>'active')::boolean); v_target := p_args->>'jobname';
  elsif p_action = 'country' then
    v_cc := upper(coalesce(p_args->>'code', ''));
    select to_jsonb(scholarship_ingestion_enabled) into v_before from ref.countries where iso_alpha2 = v_cc;
    if v_before is null then raise exception 'unknown country'; end if;
    update ref.countries set scholarship_ingestion_enabled = (p_args->>'enabled')::boolean, updated_at = now() where iso_alpha2 = v_cc;
    v_after := to_jsonb((p_args->>'enabled')::boolean); v_target := v_cc;
  elsif p_action = 'feed' then
    select to_jsonb(e) into v_before from pipeline.scholarship_etl_schedules e where e.feed = p_args->>'feed';
    if v_before is null then raise exception 'unknown feed'; end if;
    if p_args ? 'cadence_hours' and ((p_args->>'cadence_hours') !~ '^[0-9]+$' or (p_args->>'cadence_hours')::int not between 24 and 2160) then raise exception 'enter a cadence from 24 to 2160 hours'; end if;
    update pipeline.scholarship_etl_schedules set enabled = coalesce((p_args->>'enabled')::boolean, enabled), cadence_hours = coalesce((p_args->>'cadence_hours')::int, cadence_hours), updated_at = now() where feed = p_args->>'feed';
    select to_jsonb(e) into v_after from pipeline.scholarship_etl_schedules e where e.feed = p_args->>'feed'; v_target := p_args->>'feed';
  elsif p_action = 'source_add' then
    v_role := p_args->>'role'; v_url := btrim(coalesce(p_args->>'url', '')); v_cc := upper(coalesce(p_args->>'country', 'ALL'));
    if v_role not in ('ingest', 'provider_pages', 'reference', 'validation') then raise exception 'choose how the source is used'; end if;
    if v_url !~* '^https?://[^[:space:]]+\.[^[:space:]]+$' then raise exception 'enter the full address, starting with https://'; end if;
    if coalesce(btrim(p_args->>'label'), '') = '' then raise exception 'give the source a name'; end if;
    if v_cc <> 'ALL' and not exists (select 1 from ref.countries where iso_alpha2 = v_cc) then raise exception 'unknown country'; end if;
    if exists (select 1 from pipeline.sources where url = v_url) then raise exception 'this address is already registered'; end if;
    insert into pipeline.sources(source_type, country_id, url, label, trust_rank, status, metadata)
    values (case when v_role in ('reference', 'validation') then 'scholarship_reference' else 'scholarship_catalogue' end,
            (select id from ref.countries where iso_alpha2 = v_cc), v_url, btrim(p_args->>'label'), case when v_role in ('reference', 'validation') then 30 else 80 end,
            case when v_role in ('reference', 'validation') then 'active' else 'registered' end,
            jsonb_build_object('domain', 'scholarship', 'scholarship_role', v_role, 'reader', 'none', 'use', nullif(btrim(coalesce(p_args->>'use', '')), ''), 'added_by', auth.uid(), 'decision', 'Decision 251'))
    returning id into v_id;
    v_after := jsonb_build_object('id', v_id, 'url', v_url, 'role', v_role, 'country', v_cc); v_target := btrim(p_args->>'label');
  elsif p_action in ('source_role', 'source_status') then
    v_id := (p_args->>'id')::uuid;
    select jsonb_build_object('role', metadata->>'scholarship_role', 'status', status), label into v_before, v_target from pipeline.sources where id = v_id and source_type in ('government_scholarship_program', 'scholarship_catalogue', 'scholarship_reference');
    if v_before is null then raise exception 'unknown scholarship source'; end if;
    if p_action = 'source_role' then
      if p_args->>'role' not in ('ingest', 'provider_pages', 'reference', 'validation') then raise exception 'choose how the source is used'; end if;
      update pipeline.sources set metadata = metadata || jsonb_build_object('scholarship_role', p_args->>'role'), updated_at = now() where id = v_id;
    else
      if p_args->>'status' not in ('active', 'paused') then raise exception 'choose on or paused'; end if;
      if v_before->>'status' = 'registered' and p_args->>'status' = 'active' and not exists (select 1 from pipeline.scholarship_etl_schedules e join pipeline.sources x on x.metadata->>'scholarship_source_key' = e.source_key where x.id = v_id) and (select metadata->>'scholarship_role' from pipeline.sources where id = v_id) in ('ingest', 'provider_pages') then
        raise exception 'no reader exists for this source yet; it stays registered';
      end if;
      update pipeline.sources set status = p_args->>'status', updated_at = now() where id = v_id;
      update pipeline.scholarship_etl_schedules e set enabled = (p_args->>'status' = 'active'), updated_at = now() from pipeline.sources x where x.id = v_id and e.source_key = x.metadata->>'scholarship_source_key';
    end if;
    select jsonb_build_object('role', metadata->>'scholarship_role', 'status', status) into v_after from pipeline.sources where id = v_id;
  else
    raise exception 'unknown action';
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('scholarships', 'layer_' || p_action, v_target, jsonb_build_object('before', v_before, 'after', v_after, 'reason', v_reason, 'decision', 'Decision 251'), auth.uid());
  return jsonb_build_object('ok', true, 'action', p_action, 'target', v_target, 'after', v_after);
end $function$
