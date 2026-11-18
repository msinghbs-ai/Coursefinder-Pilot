-- CF-247 F-PDESC follow-up to 20261110250000 (live, 10 Nov 2026 23:16 AEDT): with pdesc.dispatch_max 3 the fire sent three worker calls at
-- the same second; public.svc_provider_description_next took its capacity lock with pg_try_advisory_xact_lock, so two of the three found it
-- held and returned idle (capacity_in_flight) after doing nothing. The lease now waits for its turn on the same lock, at most 5 seconds
-- (a lease takes milliseconds; svc_provider_description_record already waits on this lock), and is idle as before only if the turn does not
-- come. Every capacity, spend, Firecrawl and pick rule after the lock is unchanged.
-- No setting, job or consumer object (G1, G2, G3). Forward recovery: the inverse replacement (pg_try_advisory_xact_lock line), md5-guarded.
-- Replaces: the try-lock line of svc_provider_description_next.
-- Retires: nothing.

do $f$
declare d text := pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure);
        o text := $o$  if not pg_try_advisory_xact_lock(hashtext('cf247 provider description capacity')) then return jsonb_build_object('idle',true,'reason','capacity_in_flight','items','[]'::jsonb); end if;$o$;
        n text := $n$  -- 20261110252000: the calls of one fire take turns on the capacity lock (at most 5 s, fixed: a lease takes milliseconds) instead of giving up at once
  declare v_lt text := current_setting('lock_timeout');
  begin
    perform set_config('lock_timeout', '5s', true);
    perform pg_advisory_xact_lock(hashtext('cf247 provider description capacity'));
    perform set_config('lock_timeout', v_lt, true);
  exception when lock_not_available then
    perform set_config('lock_timeout', v_lt, true);
    return jsonb_build_object('idle',true,'reason','capacity_in_flight','items','[]'::jsonb);
  end;$n$;
begin
  if md5(d) <> '82bfe2daae5c95059ada6aa6305e0dde' then raise exception 'svc_provider_description_next is not the 20261110250000 body (%)', md5(d); end if;
  if (length(d) - length(replace(d, o, ''))) / length(o) <> 1 then raise exception 'next: the capacity try-lock is not found exactly once'; end if;
  execute replace(d, o, n);
  if position('20261110252000' in pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure)) = 0 then raise exception 'post-check: next not changed'; end if;
end $f$;
