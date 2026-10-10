create or replace function public.layer4_publication_state(
  p_entity_type text,p_entity_id uuid,p_target_scope text default 'governed_publication'
) returns jsonb language sql stable security definer
set search_path='pg_catalog','public','security','auth'
as $$ select security.layer4_publication_state_read(p_entity_type,p_entity_id,p_target_scope) $$;
revoke all on function public.layer4_publication_state(text,uuid,text) from public,anon;
grant execute on function public.layer4_publication_state(text,uuid,text) to authenticated,service_role;