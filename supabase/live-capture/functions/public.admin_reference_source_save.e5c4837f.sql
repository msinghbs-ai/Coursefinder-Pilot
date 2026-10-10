CREATE OR REPLACE FUNCTION public.admin_reference_source_save(p_id uuid, p_fields jsonb, p_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_old pipeline.important_links%rowtype; v_new pipeline.important_links%rowtype;
        v_reason text := nullif(btrim(coalesce(p_reason, '')), ''); v_changed text[]; v_inuse bigint;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;
  if p_fields is null or jsonb_typeof(p_fields) <> 'object' then raise exception 'nothing to save'; end if;
  if exists (select 1 from jsonb_object_keys(p_fields) k where k not in ('name','url','purpose','country','category','domain','uses','enabled','ref_key')) then
    raise exception 'unknown field'; end if;
  if p_id is null or exists (select 1 from jsonb_object_keys(p_fields) k where k in ('domain','uses','enabled','ref_key','category')) then
    if v_rank < 5 then raise exception 'PIM Operator role or above required to add a site or change how it is used' using errcode = '42501'; end if;
    if v_reason is null or length(v_reason) < 3 then raise exception 'give a short reason'; end if;
  end if;
  if p_id is null then
    insert into pipeline.important_links(country_code, authority_category, authority_name, url, domain, uses, enabled, ref_key, purpose, owner_label,
      verification_cadence, next_verification_at, health_status, change_control_ref, created_by, updated_by)
    values (upper(coalesce(nullif(btrim(p_fields->>'country'), ''), 'ALL')), coalesce(p_fields->>'category', 'third_party_directory'),
      btrim(coalesce(p_fields->>'name', '')), btrim(coalesce(p_fields->>'url', '')), nullif(lower(btrim(coalesce(p_fields->>'domain', ''))), ''),
      coalesce((select array_agg(x) from jsonb_array_elements_text(p_fields->'uses') x), array['reference']::text[]),
      coalesce((p_fields->>'enabled')::boolean, true), nullif(btrim(coalesce(p_fields->>'ref_key', '')), ''), btrim(coalesce(p_fields->>'purpose', '')),
      'CourseFinder Data Ops', interval '90 days', now() + interval '90 days', 'unverified', 'CF-CHG-20260915-247', auth.uid(), auth.uid())
    returning * into v_new;
    if length(v_new.authority_name) < 2 then raise exception 'give the site a name'; end if;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('reference_sources', 'add', v_new.authority_name, jsonb_build_object('id', v_new.id, 'domain', v_new.domain, 'uses', to_jsonb(v_new.uses), 'reason', v_reason), auth.uid());
    return public.admin_reference_sources_read() || jsonb_build_object('saved', v_new.id);
  end if;
  select * into v_old from pipeline.important_links where id = p_id for update;
  if not found then raise exception 'site not found'; end if;
  update pipeline.important_links set
    authority_name = case when p_fields ? 'name' then btrim(p_fields->>'name') else authority_name end,
    url = case when p_fields ? 'url' then btrim(p_fields->>'url') else url end,
    purpose = case when p_fields ? 'purpose' then btrim(coalesce(p_fields->>'purpose', '')) else purpose end,
    country_code = case when p_fields ? 'country' then upper(coalesce(nullif(btrim(p_fields->>'country'), ''), 'ALL')) else country_code end,
    authority_category = case when p_fields ? 'category' then p_fields->>'category' else authority_category end,
    domain = case when p_fields ? 'domain' then nullif(lower(btrim(coalesce(p_fields->>'domain', ''))), '') else domain end,
    uses = case when p_fields ? 'uses' then coalesce((select array_agg(x) from jsonb_array_elements_text(p_fields->'uses') x), array[]::text[]) else uses end,
    enabled = case when p_fields ? 'enabled' then (p_fields->>'enabled')::boolean else enabled end,
    ref_key = case when p_fields ? 'ref_key' then nullif(btrim(coalesce(p_fields->>'ref_key', '')), '') else ref_key end,
    updated_by = auth.uid(), updated_at = now()
  where id = p_id returning * into v_new;
  if length(coalesce(v_new.authority_name, '')) < 2 then raise exception 'give the site a name'; end if;
  if 'scholarship_placeholder' = any(v_old.uses) and v_old.enabled and v_old.retired_at is null
     and (not v_new.enabled or not ('scholarship_placeholder' = any(v_new.uses)) or v_new.domain is distinct from v_old.domain) then
    v_inuse := security.reference_placeholder_in_use(v_old.domain);
    if v_inuse > 0 then raise exception '% active scholarships are sourced only from this site; they would look publishable. Give them a university page first.', v_inuse; end if;
  end if;
  select array_agg(k) into v_changed from jsonb_object_keys(p_fields) k;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('reference_sources', 'change', v_new.authority_name, jsonb_build_object('id', p_id, 'fields', to_jsonb(v_changed),
          'before', jsonb_build_object('name', v_old.authority_name, 'url', v_old.url, 'domain', v_old.domain, 'uses', to_jsonb(v_old.uses),
                    'enabled', v_old.enabled, 'category', v_old.authority_category, 'country', v_old.country_code, 'ref_key', v_old.ref_key, 'purpose', v_old.purpose),
          'reason', v_reason), auth.uid());
  return public.admin_reference_sources_read() || jsonb_build_object('saved', p_id);
end $function$
