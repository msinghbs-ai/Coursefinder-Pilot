-- CF-247, 7 Oct 2026: automatic adapter build, part 5 of 6: a Platform Admin admits the fields a finished build found ready.
-- A deliberate step with a reason: only fields listed as ready by the provider's latest finished build, added to the fields already admitted.
create or replace function public.admin_adapter_autobuild_admit(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_reason text := btrim(coalesce(p_args->>'reason', ''));
        b pipeline.adapter_autobuilds%rowtype; v_ready text[]; v_pick text[]; v_cur text[];
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  select * into b from pipeline.adapter_autobuilds where provider_id = v_pid order by created_at desc limit 1;
  if not found or b.status <> 'done' then raise exception 'no finished automatic build for this provider'; end if;
  v_ready := array(select jsonb_array_elements_text(coalesce(b.result->'ready', '[]'::jsonb)));
  v_pick := case when p_args ? 'fields' then array(select x from jsonb_array_elements_text(p_args->'fields') x where x = any(v_ready)) else v_ready end;
  if cardinality(v_pick) = 0 then raise exception 'none of these fields is ready to admit'; end if;
  select coalesce(admit_fields, '{}') into v_cur from pipeline.uni_adapters where provider_id = v_pid;
  perform public.admin_uni_adapter_control('admit', jsonb_build_object('provider_id', v_pid, 'admit', true,
           'fields', to_jsonb(array(select distinct x from unnest(coalesce(v_cur, '{}') || v_pick) x order by 1)), 'reason', v_reason));
  update pipeline.adapter_autobuilds set result = result || jsonb_build_object('admitted', to_jsonb(v_pick), 'admitted_by', auth.uid(), 'admitted_at', now()),
         note = 'Admitted by a Platform Admin: ' || array_to_string(v_pick, ', ') || '.', updated_at = now() where id = b.id;
  return jsonb_build_object('ok', true, 'admitted', to_jsonb(v_pick));
end $f$;
revoke all on function public.admin_adapter_autobuild_admit(jsonb) from public, anon;
grant execute on function public.admin_adapter_autobuild_admit(jsonb) to authenticated, service_role;
