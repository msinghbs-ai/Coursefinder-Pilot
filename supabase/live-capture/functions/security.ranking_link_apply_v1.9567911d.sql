CREATE OR REPLACE FUNCTION security.ranking_link_apply_v1(p_pub uuid, p_provider uuid, p_method text, p_note text, p_actor uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_pi ranking.publisher_institutions%rowtype; v_sys text; v_cur uuid; v_equiv uuid[]; v_n int := 0; o record; v_pid uuid;
begin
  select * into v_pi from ranking.publisher_institutions where id = p_pub;
  if v_pi.id is null then raise exception 'publisher institution not found'; end if;
  select code into v_sys from ranking.systems where id = v_pi.system_id;
  select provider_id into v_cur from ranking.provider_mappings where publisher_institution_id = p_pub and status = 'accepted' and valid_to is null;
  if v_cur is not null and v_cur <> p_provider then raise exception 'already linked to another provider'; end if;
  if v_cur is null then
    update ranking.provider_mappings set status = 'superseded' where publisher_institution_id = p_pub and status = 'candidate';
    insert into ranking.provider_mappings(publisher_institution_id, provider_id, mapping_method, confidence, status, reviewed_by, reviewed_at, note)
    values (p_pub, p_provider, p_method, 1.0, 'accepted', p_actor, now(), p_note);
  end if;
  v_equiv := public.svc_statistical_equivalent_provider_ids(p_provider);
  for o in select id from ranking.observations where publisher_institution_id = p_pub and provider_id is null loop
    update ranking.observations set provider_id = p_provider where id = o.id;
    foreach v_pid in array v_equiv loop
      insert into ranking.observation_provider_links(observation_id, provider_id, link_method, is_primary)
      values (o.id, v_pid, case when v_pid = p_provider then 'primary_' || p_method else 'equivalent_exact_name_or_identifier' end, v_pid = p_provider)
      on conflict do nothing;
    end loop;
    v_n := v_n + 1;
  end loop;
  insert into catalogue.provider_aliases(provider_id, alias, alias_type)
  values (p_provider, v_pi.institution_name, v_sys || '_publisher_name')
  on conflict (provider_id, alias, coalesce(locale, '')) do nothing;
  return v_n;
end $function$
