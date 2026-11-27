-- CF-247 s1313b (S1-Build, 27 Nov 2026 17:00 AEDT): restore the scholarship listing picker's provider hold (production regression from s1313).
-- Found live after s1313 (Pilot #1731, 16:34 AEDT): the eligibility rule costs about 200 ms a provider (security.fc_sch_eligible_v1), and with
-- the paid cap no longer short-circuiting it, the picker evaluated it for every provider with due pages (73: 15 s; the whole call 12.9 s). The
-- worker's call runs under the 8 s statement limit, so public.svc_scholarship_listing_next timed out (lane call 05:37 UTC: HTTP 500 "canceling
-- statement due to statement timeout") and no listing page was read. This puts back the predicate as it was before s1313 (fc_sch_held_v1),
-- which evaluates eligibility only for providers under their cap. security.fc_sch_listing_held_v1 is kept, unused (nothing is dropped).
-- D12 stays open: a held provider's free reads need an eligibility check that fits the call (for example a bounded candidate pool), a separate
-- change for the Platform Admin.
-- G1: no job. G2: no new value. G3: 75/48 checked. Nothing dropped or deleted.
-- Replaces: public.svc_scholarship_listing_next (md5 7916b690; the s1313 predicate back to fc_sch_held_v1).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the replaced function

do $pre$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then
    raise exception 'pre-check: consumer API baseline is not 75/48 with no drift: %', v;
  end if;
  if md5(pg_get_functiondef('public.svc_scholarship_listing_next(integer)'::regprocedure)) <> '7916b69090a4cfb36bb703154f8008ef' then
    raise exception 'pre-check: public.svc_scholarship_listing_next is not the s1313 definition';
  end if;
end $pre$;

do $edit$
declare d text := pg_get_functiondef('public.svc_scholarship_listing_next(integer)'::regprocedure);
        a text := 'and not security.fc_sch_listing_held_v1(d.provider_id)),  -- s1313: eligibility only; the paid cap is enforced on each paid scrape (svc_fc_spend)';
begin
  if position(a in d) = 0 then raise exception 'anchor not found in svc_scholarship_listing_next'; end if;
  d := replace(d, a, 'and not security.fc_sch_held_v1(d.provider_id, true)),');
  execute d;
end $edit$;

do $post$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API baseline changed: %', v; end if;
  if md5(pg_get_functiondef('public.svc_scholarship_listing_next(integer)'::regprocedure)) <> 'dc3b688512a12d5bbf3ed16eecdbd796' then
    raise exception 'post-check: the picker is not back to its definition before s1313';
  end if;
end $post$;
