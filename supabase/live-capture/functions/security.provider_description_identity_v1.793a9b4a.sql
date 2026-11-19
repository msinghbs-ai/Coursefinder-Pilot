CREATE OR REPLACE FUNCTION security.provider_description_identity_v1(p_provider uuid, p_url text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p catalogue.providers%rowtype; v_finding text; v_other uuid; v_host text; v_owner uuid;
begin
  select * into p from catalogue.providers where id = p_provider;
  if p.id is null or p.lifecycle_status <> 'active' or p.publication_status <> 'published'
     or exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p_provider)
     or security.provider_lifecycle_held_v1(p_provider) then
    return jsonb_build_object('ok', false, 'rule', 'provider_inactive', 'reason', 'The provider is not active and published, or its lifecycle is held.');
  end if;
  select f.check_code into v_finding from pipeline.provider_identity_findings f
   where f.provider_id = p_provider and f.state = 'open'
   order by f.check_code limit 1;
  if v_finding is not null then
    return jsonb_build_object('ok', false, 'rule', 'identity_' || v_finding,
      'reason', 'An existing provider identity finding requires resolution: ' || v_finding);
  end if;
  if security.provider_page_host_v1(p_provider, p_url) <> 'own' then
    return jsonb_build_object('ok', false, 'rule', 'wrong_host', 'reason', 'The source is not on an approved provider host.');
  end if;
  -- s766: a host with a recorded owner is decided by the record. The owner is clear; any other provider that holds the host stays in conflict.
  v_host := security.site_host_v1(p_url);
  select o.owner_provider_id into v_owner from pipeline.provider_host_owners o
   where v_host is not null and o.host = v_host
     and exists (select 1 from catalogue.providers w where w.id = o.owner_provider_id and w.lifecycle_status = 'active');
  if v_owner = p_provider then
    return jsonb_build_object('ok', true, 'rule', 'identity_clear', 'via', 'recorded_host_owner');
  end if;
  if v_owner is not null then
    return jsonb_build_object('ok', false, 'rule', 'provider_host_conflict', 'conflicting_provider_id', v_owner,
      'reason', 'Another active provider is the recorded owner of the source host; exact provider identity requires resolution.');
  end if;
  -- Even an own host is ambiguous when it is another current provider's primary host.
  -- Never infer that a university and similarly named college are interchangeable.
  select o.id into v_other from catalogue.providers o
   where o.id <> p_provider and o.lifecycle_status = 'active'
     and security.site_host_v1(o.website) = security.site_host_v1(p_url)
     and security.site_host_v1(p_url) is not null
   order by o.id limit 1;
  if v_other is not null then
    return jsonb_build_object('ok', false, 'rule', 'provider_host_conflict', 'conflicting_provider_id', v_other,
      'reason', 'Another active provider holds the source host; exact provider identity requires resolution.');
  end if;
  return jsonb_build_object('ok', true, 'rule', 'identity_clear');
end $function$
