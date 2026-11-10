-- Forward recovery for 20261110250000_cf247_pdesc_autonomous_throughput.sql (apply as a NEW migration only if that change must be undone).
-- Inverse of each replacement (exact text), the job unscheduled, the settings put back. The self-heal function and the three new settings
-- are left in place (inert once the job is unscheduled). No description, read or ledger row is changed.
do $r$
declare d text; o text; n text;
begin
  -- first undo 20261110252000 (the lease waits its turn) so the md5 checks below hold
  d := pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure);
  o := $o$  -- 20261110252000: the calls of one fire take turns on the capacity lock (at most 5 s, fixed: a lease takes milliseconds) instead of giving up at once
  declare v_lt text := current_setting('lock_timeout');
  begin
    perform set_config('lock_timeout', '5s', true);
    perform pg_advisory_xact_lock(hashtext('cf247 provider description capacity'));
    perform set_config('lock_timeout', v_lt, true);
  exception when lock_not_available then
    perform set_config('lock_timeout', v_lt, true);
    return jsonb_build_object('idle',true,'reason','capacity_in_flight','items','[]'::jsonb);
  end;$o$;
  n := $n$  if not pg_try_advisory_xact_lock(hashtext('cf247 provider description capacity')) then return jsonb_build_object('idle',true,'reason','capacity_in_flight','items','[]'::jsonb); end if;$n$;
  if position(o in d) > 0 then execute replace(d, o, n); end if;
  if md5(pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure)) <> '82bfe2daae5c95059ada6aa6305e0dde' then raise exception 'next is not the 20261110250000 body after undoing 20261110252000'; end if;

  d := pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure);
  n := $n$  if coalesce((p_result->>'about_page')::boolean, false) is false or v_n = 0 then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'not_stated', 'checks', v_checks, 'reason', 'the page does not describe the institution');
  end if;$n$;
  o := $o$  if v_n = 0 then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'not_stated', 'checks', v_checks, 'reason', 'the page does not describe the institution');
  end if;
  -- CF-247 F-PDESC (20261110250000): the model's about_page flag no longer vetoes sentences; it is recorded and every sentence rule below decides
  if coalesce((p_result->>'about_page')::boolean, false) is false then v_checks := v_checks || jsonb_build_object('about_page_flag', false); end if;$o$;
  if position(o in d) = 0 then raise exception 'validate_v1 is not the 20261110250000 body'; end if;
  execute replace(d, o, n);
  if md5(pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure)) <> '35d6d53240c1da35ecc6d28f31ccd1df' then raise exception 'validate_v1 recovery md5 mismatch'; end if;

  d := pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure);
  o := $o$  select coalesce(sum(r.firecrawl_reads), 0) into v_fc_used from pipeline.provider_description_reads r
   where r.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.firecrawl_window_hours', 24)::int); -- 20261110250000: an allowance a window, not a lifetime count$o$;
  n := $n$  select coalesce(sum(r.firecrawl_reads), 0) into v_fc_used from pipeline.provider_description_reads r;$n$;
  if position(o in d) = 0 then raise exception 'next is not the 20261110250000 body'; end if;
  execute replace(d, o, n);
  if md5(pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure)) <> 'b87f37cc18947a976c432f07f65b1fc4' then raise exception 'next recovery md5 mismatch'; end if;

  if to_regnamespace('cron') is not null and exists (select 1 from cron.job where jobname = 'provider-description-self-heal') then perform cron.unschedule('provider-description-self-heal'); end if;
  update pipeline.platform_toolset_settings set value = '20'::jsonb, updated_at = now(), reason = 'forward recovery of 20261110250000' where toolset_key = 'pipeline' and key = 'pdesc.firecrawl_reads_max';
  update pipeline.platform_toolset_settings set value = '5'::jsonb, updated_at = now(), reason = 'forward recovery of 20261110250000' where toolset_key = 'pipeline' and key = 'pdesc.firecrawl_per_call';
  update pipeline.platform_toolset_settings set value = '1'::jsonb, updated_at = now(), reason = 'forward recovery of 20261110250000' where toolset_key = 'pipeline' and key = 'pdesc.dispatch_max';
  -- undo 20261110253000 (five-minute cadence)
  update pipeline.platform_toolset_settings set value = '10'::jsonb, min_value = 10, updated_at = now(), reason = 'forward recovery of 20261110253000' where toolset_key = 'pipeline' and key = 'pdesc.every_minutes';
  if to_regnamespace('cron') is not null then
    perform cron.alter_job((select jobid from cron.job where jobname = 'provider-description-read'), schedule := '6,16,26,36,46,56 * * * *');
  end if;
  update pipeline.platform_toolset_settings set value = '12'::jsonb, updated_at = now(), reason = 'forward recovery of 20261110250000' where toolset_key = 'pipeline' and key = 'pdesc.concurrency_max';
end $r$;
