CREATE OR REPLACE FUNCTION public.admin_provider_description_fill_v1(p_provider_ids uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- CF-247 F-PDESC (Platform Admin 11 Nov 2026 14:57): "a simple button to fill in a provider's description". Each provider is queued at the
-- front (checks.on_demand) and a worker call is started at once. Not held by the lane AI ceiling, the lane daily guard, the Firecrawl allowance
-- or share, or the "same page already failed" memory; a manual lock, the identity proof and the platform-wide AI rule still apply.
declare v_out jsonb := '[]'::jsonb; v_pid uuid; p catalogue.providers%rowtype; r pipeline.provider_description_reads%rowtype; v_q int := 0; v_word text;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'An operator is required' using errcode = '42501'; end if;
  if coalesce(array_length(p_provider_ids, 1), 0) = 0 then raise exception 'choose at least one provider'; end if;
  if array_length(p_provider_ids, 1) > security.pipeline_num_v1('pdesc.fill_max_per_click', 25) then
    raise exception 'one click fills at most % providers (Settings › Pipeline settings › Provider descriptions)', security.pipeline_num_v1('pdesc.fill_max_per_click', 25)::int;
  end if;
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then raise exception 'The provider description reader is switched off'; end if;
  foreach v_pid in array p_provider_ids loop
    select * into p from catalogue.providers where id = v_pid;
    v_word := null;
    if p.id is null then v_word := 'not_found';
    elsif exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all')) then v_word := 'manual';
    elsif nullif(btrim(p.description), '') is not null and security.provider_description_basic_profile_v1(p.id) is null then v_word := 'has_description';
    elsif p.lifecycle_status <> 'active' or p.publication_status <> 'published' then v_word := 'not_live';
    elsif not coalesce((security.provider_description_identity_v1(p.id, coalesce((select a.source_url from pipeline.evidence_artifacts a where a.id = security.provider_description_stored_v1(p.id)), p.website))->>'ok')::boolean, false) then v_word := 'identity';
    end if;
    if v_word is null then
      select * into r from pipeline.provider_description_reads x where x.provider_id = p.id and x.state in ('queued', 'reading', 'proposed') limit 1;
      if r.id is not null and r.state in ('reading', 'proposed') then v_word := 'in_progress';
      elsif r.id is not null then
        update pipeline.provider_description_reads set next_try_at = now(), tries = 0, updated_at = now(),
               checks = coalesce(checks, '{}'::jsonb) || jsonb_build_object('on_demand', jsonb_build_object('by', auth.uid(), 'at', now()))
         where id = r.id;
        v_word := 'queued'; v_q := v_q + 1;
      else
        -- a new read: earlier reads stay as they are (the admission ledger refers to them)
        insert into pipeline.provider_description_reads(provider_id, state, next_try_at, reason, checks)
        values (p.id, 'queued', now(), 'Operator asked to fill the description (on demand)', jsonb_build_object('on_demand', jsonb_build_object('by', auth.uid(), 'at', now())));
        v_word := 'queued'; v_q := v_q + 1;
      end if;
    end if;
    v_out := v_out || jsonb_build_object('provider_id', v_pid, 'name', coalesce(p.display_name, p.canonical_name), 'outcome', v_word);
  end loop;
  if v_q > 0 then
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_description', 'limit', security.pipeline_num_v1('batch.provider_description', 3)::int));
  end if;
  return jsonb_build_object('queued', v_q, 'providers', v_out);
end $function$
