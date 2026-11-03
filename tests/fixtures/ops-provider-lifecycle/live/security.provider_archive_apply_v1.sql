CREATE OR REPLACE FUNCTION security.provider_archive_apply_v1(p_provider_id uuid, p_source text, p_reason text, p_actor uuid, p_manual boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_life text; v_pub text; v_now text; v_ad int; v_lr int; v_rv jsonb; v_id bigint;
begin
  select p.lifecycle_status, p.publication_status into v_life, v_pub from catalogue.providers p where p.id = p_provider_id for update;
  if not found then raise exception 'provider not found'; end if;
  if v_life = 'archived' then return jsonb_build_object('status', 'already_archived', 'provider_id', p_provider_id); end if;
  if p_manual then perform set_config('cf.manual_edit', 'on', true); end if;
  update catalogue.providers set lifecycle_status = 'archived', publication_status = 'unpublished', updated_at = now() where id = p_provider_id;
  select p.lifecycle_status into v_now from catalogue.providers p where p.id = p_provider_id;
  if v_now <> 'archived' then return jsonb_build_object('status', 'kept_by_hand', 'provider_id', p_provider_id); end if;
  with a as (update pipeline.uni_adapters set enabled = false, updated_at = now() where provider_id = p_provider_id and enabled returning 1) select count(*) into v_ad from a;
  with r as (update pipeline.course_link_recipes set active = false, updated_at = now() where provider_id = p_provider_id and active returning 1) select count(*) into v_lr from r;
  with i as (update pipeline.layer4_review_items x set status = 'superseded', decided_at = now()
              where x.status = 'pending' and ((x.entity_type = 'provider' and x.entity_id = p_provider_id)
                    or (x.entity_type = 'course' and x.entity_id in (select c.id from catalogue.courses c where c.provider_id = p_provider_id)))
             returning x.id)
  select coalesce(jsonb_agg(i.id), '[]'::jsonb) into v_rv from i;
  insert into pipeline.provider_archives(provider_id, source, reason, previous_lifecycle, previous_publication, cascade, archived_by)
  values (p_provider_id, p_source, left(btrim(coalesce(nullif(p_reason, ''), 'Archived')), 500), v_life, v_pub,
          jsonb_build_object('adapter_switched_off', v_ad > 0, 'link_recipe_switched_off', v_lr > 0, 'reviews_superseded', v_rv), p_actor)
  returning id into v_id;
  insert into pipeline.manual_edit_log(entity, entity_id, field, action, before, after, reason, actor)
  values ('provider', p_provider_id, 'lifecycle_status', 'archive', to_jsonb(v_life), to_jsonb('archived'::text), left(p_source || ': ' || coalesce(p_reason, ''), 500), p_actor);
  insert into search.refresh_requests(requested_by) values (format('provider %s archived (%s)', left(p_provider_id::text, 8), p_source));
  return jsonb_build_object('status', 'archived', 'provider_id', p_provider_id, 'archive_id', v_id, 'adapter_switched_off', v_ad > 0,
                            'link_recipe_switched_off', v_lr > 0, 'reviews_superseded', jsonb_array_length(v_rv));
end $function$

