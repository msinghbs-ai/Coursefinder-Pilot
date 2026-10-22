-- CF-247 (23 Oct 2026). public.svc_programme_record failed on every programme page ("null character not permitted": chr(0) cannot be
-- used in PostgreSQL text), so the first 40 Université de Montréal programme pages read were not recorded. jsonb cannot hold a null
-- character, so the worker removes them before sending (v0.40.6) and the recorder no longer mentions it.
-- Replaces: public.svc_programme_record (20261022043000; replaced in full, same signature)
-- Retires: nothing
create or replace function public.svc_programme_record(p_id bigint, p_result jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare v_c pipeline.programme_candidates; v_country text; v_heading text; v_title text; v_level text; v_status text := coalesce(p_result->>'status', 'failed');
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into v_c from pipeline.programme_candidates where id = p_id;
  if v_c.id is null then return jsonb_build_object('error', 'unknown candidate'); end if;
  v_country := security.coverage_country(v_c.provider_id);
  -- 23 Oct 2026: jsonb cannot hold a null character, so none reaches here (the worker removes them); chr(0) itself is refused by PostgreSQL
  v_heading := nullif(btrim(left(p_result->>'heading', 300)), '');
  v_title := nullif(btrim(left(coalesce(p_result->>'og_title', p_result->>'title'), 300)), '');
  if v_status in ('read', 'too_thin') and coalesce(v_heading, v_title) is not null then
    v_level := coalesce(security.credential_level_v1(v_country, v_heading), security.credential_level_v1(v_country, v_title));
    update pipeline.programme_candidates set state = 'read', heading = coalesce(v_heading, v_title), page_title = v_title, final_url = p_result->>'final_url',
           study_level_code = v_level, http_status = (p_result->>'http')::int, fetched_via = p_result->>'via', read_at = now(), leased_until = null, updated_at = now(),
           outcome = case when v_level is null then 'no_level' end
     where id = p_id;
  else
    update pipeline.programme_candidates set state = case when v_status = 'gone' then 'gone' else 'failed' end, http_status = (p_result->>'http')::int,
           fetched_via = p_result->>'via', read_at = now(), leased_until = null, updated_at = now(), outcome = v_status,
           next_read_at = now() + interval '1 day'  -- fixed: a failed page is tried again the next day
     where id = p_id;
  end if;
  return jsonb_build_object('level', v_level);
end $function$;
revoke all on function public.svc_programme_record(bigint, jsonb) from public, anon, authenticated;
grant execute on function public.svc_programme_record(bigint, jsonb) to service_role;

select 'programme page record fixed' ok;

do $t$ declare r jsonb; begin
  r := public.svc_programme_record((select id from pipeline.programme_candidates order by id limit 1), '{"status":"read","http":200,"via":"direct","final_url":"https://admission.umontreal.ca/programmes/x/","heading":"Baccalauréat en informatique","title":"t","og_title":null}'::jsonb);
  raise exception 'DRYRUN OK %', r || (select jsonb_build_object('state', c.state, 'level', c.study_level_code, 'heading', c.heading) from pipeline.programme_candidates c order by c.id limit 1); end $t$;
