-- CF-247 (23 Oct 2026). public.svc_programme_source_record failed on every read ("column reference found is ambiguous": found is also
-- PL/pgSQL's own FOUND), so the Université de Montréal programme list read by the worker (1,095 programme pages) was not recorded.
-- The table's columns are now named through its alias.
-- Replaces: public.svc_programme_source_record (20261022043000; replaced in full, same signature)
-- Retires: nothing
create or replace function public.svc_programme_source_record(p_id bigint, p_status text, p_http integer, p_via text, p_urls jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_s pipeline.programme_sources; v_found int := 0; v_new int := 0;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_s from pipeline.programme_sources where id = p_id;
  if v_s.id is null then return jsonb_build_object('error', 'unknown source'); end if;
  if p_status = 'read' and jsonb_typeof(p_urls) = 'array' then
    with u as (select distinct on (x->>'url') x->>'url' url, nullif(left(x->>'title', 300), '') title
                 from jsonb_array_elements(p_urls) x where x->>'url' ~* '^https?://' and x->>'url' ~* v_s.url_pattern),
         ins as (insert into pipeline.programme_candidates(provider_id, programme_source_id, url, link_title)
                 select v_s.provider_id, v_s.id, u.url, u.title from u on conflict (provider_id, url) do nothing returning 1)
    select (select count(*) from u), (select count(*) from ins) into v_found, v_new;
  end if;
  update pipeline.programme_sources ps set status = case when p_status in ('read', 'blocked', 'gone') then p_status else 'failed' end,
         http_status = p_http, fetched_via = p_via, found = case when p_status = 'read' then v_found else ps.found end,
         found_new = case when p_status = 'read' then v_new else ps.found_new end, read_at = now(), leased_until = null, updated_at = now(),
         next_read_at = now() + make_interval(days => case when p_status = 'read' then security.pipeline_num_v1('programme.reread_days', 30)::int else 1 end)  -- fixed: a failed read is tried the next day
   where ps.id = p_id;
  return jsonb_build_object('found', v_found, 'new', v_new);
end $function$;
revoke all on function public.svc_programme_source_record(bigint, text, integer, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_programme_source_record(bigint, text, integer, text, jsonb) to service_role;

select 'programme list record fixed' ok;
