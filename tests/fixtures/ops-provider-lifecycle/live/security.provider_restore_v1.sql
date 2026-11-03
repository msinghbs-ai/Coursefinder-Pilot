CREATE OR REPLACE FUNCTION security.provider_restore_v1(p_provider_id uuid, p_note text, p_actor uuid, p_manual boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_life text; v_id bigint; v_prev_pub text; v_cascade jsonb; v_now text; v_rv int := 0;
begin
  select p.lifecycle_status into v_life from catalogue.providers p where p.id = p_provider_id for update;
  if not found then raise exception 'provider not found'; end if;
  if v_life = 'active' then return jsonb_build_object('status', 'already_active', 'provider_id', p_provider_id); end if;
  select a.id, a.previous_publication, a.cascade into v_id, v_prev_pub, v_cascade from pipeline.provider_archives a
   where a.provider_id = p_provider_id and a.restored_at is null for update;
  if p_manual then perform set_config('cf.manual_edit', 'on', true); end if;
  update catalogue.providers set lifecycle_status = 'active', publication_status = coalesce(v_prev_pub, 'published'), updated_at = now() where id = p_provider_id;
  select p.lifecycle_status into v_now from catalogue.providers p where p.id = p_provider_id;
  if v_now <> 'active' then return jsonb_build_object('status', 'kept_by_hand', 'provider_id', p_provider_id); end if;
  if v_id is not null then
    if coalesce((v_cascade->>'adapter_switched_off')::boolean, false) then update pipeline.uni_adapters set enabled = true, updated_at = now() where provider_id = p_provider_id; end if;
    if coalesce((v_cascade->>'link_recipe_switched_off')::boolean, false) then update pipeline.course_link_recipes set active = true, updated_at = now() where provider_id = p_provider_id; end if;
    with i as (update pipeline.layer4_review_items x set status = 'pending', decided_at = null
                where x.status = 'superseded' and x.id in (select (e #>> '{}')::uuid from jsonb_array_elements(coalesce(v_cascade->'reviews_superseded', '[]'::jsonb)) e)
               returning 1)
    select count(*) into v_rv from i;
    update pipeline.provider_archives set restored_at = now(), restored_by = p_actor, restore_note = left(p_note, 500) where id = v_id;
  end if;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('provider', p_provider_id, 'lifecycle_status', 'restore', to_jsonb(v_life), to_jsonb('active'::text), left(coalesce(p_note, 'Restored'), 500), p_actor);
  insert into search.refresh_requests(requested_by) values (format('provider %s restored', left(p_provider_id::text, 8)));
  return jsonb_build_object('status', 'restored', 'provider_id', p_provider_id, 'publication_status', coalesce(v_prev_pub, 'published'), 'reviews_reopened', v_rv);
end $function$

