CREATE OR REPLACE FUNCTION public.admin_provider_central_page(p_action text, p_args jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rank int := security.current_role_rank(); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_pid uuid := (p_args->>'provider_id')::uuid;
        v_kind text := p_args->>'kind'; v_url text := btrim(coalesce(p_args->>'url', '')); v_id uuid;
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if p_action not in ('add', 'read_again') then raise exception 'unknown action'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  if not exists (select 1 from catalogue.providers p where p.id = v_pid) then raise exception 'unknown provider'; end if;
  if coalesce(v_kind, '') not in ('english_policy', 'intake_calendar', 'fee_schedule') then raise exception 'kind must be english_policy, intake_calendar or fee_schedule'; end if;
  if v_url !~ '^https?://[^ ]+$' or length(v_url) not between 12 and 500 then raise exception 'give the full page address (http or https)'; end if;
  insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status)
    values (v_pid, v_kind, v_url, nullif(btrim(coalesce(p_args->>'title', '')), ''), 9, 'manual', 'found')
  on conflict (provider_id, kind, url) do update set status = 'found', attempts = 0, rank = 9, found_via = 'manual', updated_at = now() where pipeline.provider_fact_sources.provider_id = excluded.provider_id
  returning id into v_id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('toolsets', 'central_page_' || p_action, v_pid::text, jsonb_build_object('source_id', v_id, 'kind', v_kind, 'url', v_url, 'reason', v_reason), auth.uid());
  return jsonb_build_object('ok', true, 'source_id', v_id, 'note', 'The page is read through Firecrawl by the provider-facts job within about 10 minutes, then parsed into a proposal for approval in Layer 4 Review › Attributes.');
end $function$
