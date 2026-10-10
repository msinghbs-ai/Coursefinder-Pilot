CREATE OR REPLACE FUNCTION public.admin_provider_publish(p_provider_id uuid, p_published boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_before text; v_after text := case when p_published then 'published' else 'unpublished' end;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 5 then raise exception 'PIM Operator role or above required' using errcode = '42501'; end if;
  select publication_status into v_before from catalogue.providers where id = p_provider_id;
  if not found then raise exception 'provider not found'; end if;
  if p_published and exists (select 1 from catalogue.providers where id = p_provider_id and lifecycle_status <> 'active') then
    raise exception 'an archived provider cannot be published: restore it first';
  end if;
  if v_before is distinct from v_after then
    perform set_config('cf.manual_edit', 'on', true);
    update catalogue.providers set publication_status = v_after, updated_at = now() where id = p_provider_id;
    insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
    values ('provider', p_provider_id, 'publication_status', case when p_published then 'publish' else 'unpublish' end, to_jsonb(v_before), to_jsonb(v_after), null, auth.uid());
    insert into search.refresh_requests(requested_by) values (format('provider %s %s', left(p_provider_id::text, 8), v_after));
  end if;
  return jsonb_build_object('provider_id', p_provider_id, 'publication_status', v_after);
end $function$
