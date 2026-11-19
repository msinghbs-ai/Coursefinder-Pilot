CREATE OR REPLACE FUNCTION public.admin_ranking_link(p_publisher_institution_id uuid, p_action text, p_provider_id uuid DEFAULT NULL::uuid, p_note text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_cid uuid; v_n int;
begin
  if auth.uid() is null or v_rank < 3 then raise exception 'Curator role required' using errcode = '42501'; end if;
  if p_action = 'run_rules' then
    if v_rank < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
    return security.ranking_link_auto_v1();
  end if;
  if p_action not in ('link', 'reject') or p_provider_id is null then raise exception 'action must be link or reject, with a provider'; end if;
  select security.ranking_country_id(country_text) into v_cid from ranking.publisher_institutions where id = p_publisher_institution_id;
  if not found then raise exception 'publisher institution not found'; end if;
  if p_action = 'reject' then
    update ranking.provider_mappings set status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(), note = coalesce(left(p_note, 300), note)
     where publisher_institution_id = p_publisher_institution_id and provider_id = p_provider_id and status = 'candidate';
    return jsonb_build_object('rejected', true);
  end if;
  if not exists (select 1 from catalogue.providers p where p.id = p_provider_id and p.lifecycle_status = 'active' and (v_cid is null or p.country_id = v_cid)) then
    raise exception 'the provider must be active and in the same country as the ranked university';
  end if;
  v_n := security.ranking_link_apply_v1(p_publisher_institution_id, p_provider_id, 'manual_person', left(coalesce(p_note, 'Linked by a person'), 300), auth.uid());
  return jsonb_build_object('linked', true, 'observations_linked', v_n);
end $function$
