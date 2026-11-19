CREATE OR REPLACE FUNCTION security.campus_primary_apply_v1(p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_n int := 0; v_several int := 0; v_none int := 0; v_kept int := 0;
begin
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  create temp table if not exists _cpa (provider_id uuid, campus_id uuid, n int, has_primary boolean) on commit drop;
  truncate _cpa;
  insert into _cpa
  select p.id, (array_agg(k.id order by k.id))[1], count(k.id),
         exists (select 1 from catalogue.campuses x where x.provider_id = p.id and x.is_primary)
    from catalogue.providers p
    left join catalogue.campuses k
      on k.provider_id = p.id and k.status = 'active'
     and lower(regexp_replace(btrim(k.address_line1), '\s+', ' ', 'g')) = lower(regexp_replace(btrim(p.address_line1), '\s+', ' ', 'g'))
     and btrim(coalesce(k.postcode, '')) = btrim(coalesce(p.postcode, ''))
   where nullif(btrim(p.address_line1), '') is not null
     and exists (select 1 from catalogue.provider_registrations r where r.provider_id = p.id and r.registration_scheme = 'cricos')
   group by p.id;
  select count(*) filter (where n = 1 and not has_primary), count(*) filter (where n > 1), count(*) filter (where n = 0), count(*) filter (where has_primary)
    into v_n, v_several, v_none, v_kept from _cpa;
  if p_apply and v_n > 0 then
    update catalogue.campuses k set is_primary = true, primary_basis = 'cricos_head_office'
      from _cpa c where c.n = 1 and not c.has_primary and k.id = c.campus_id and k.is_primary is distinct from true;
    get diagnostics v_n = row_count;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('api_v3', 'campus_primary_apply', 'catalogue.campuses.is_primary',
            jsonb_build_object('basis', 'cricos_head_office', 'marked', v_n, 'several', v_several, 'no_match', v_none, 'already_primary', v_kept), auth.uid());
  end if;
  return jsonb_build_object('applied', p_apply, 'marked', v_n, 'several_matches', v_several, 'no_match', v_none, 'already_primary', v_kept);
end;
$function$
