-- CF-247 s1355 (S1-RM-Design; SS-Programme-Control 28 Nov 2026 PC-20261128-CONTINUOUS-BUILD-EXECUTE: "support explicit valid source
-- currency, no assumed AUD, hold ambiguous source, preserve distinct components"; design record admin docs/platform/
-- 2026-11-28-s1-rm-design-country-neutral-identity-and-fee-grain-review.md, admin #1376). Database side only; the worker side is s1354 (#1762).
-- Cause: seven shared fee writers assumed Australia. Three wrote currency 'AUD' as a fixed value (fee wording rules, provider rules, provider
-- basis rules), course facts defaulted a missing currency to AUD, the adapter overwrite used a fixed NZ/CA/else-AUD map, and the Layer 4
-- apply and the Layer 3 assumed-annual admission accepted only AUD/NZD/CAD (a GBP or EUR fee was refused, and a missing currency passed as null
-- because "null not in (...)" is not true).
-- Fix: one resolver, security.fee_currency_resolve_v1(provider, explicit): an explicit active ISO code from ref.currencies wins (a genuine
-- cross-currency fee is kept); with no explicit code, the provider country's default currency (ref.countries.default_currency_code, when it
-- is an active currency); otherwise null, and every writer holds the fee (counted as currency_unknown or refused with a reason). The rule
-- paths pass 'AUD' as explicit only when the matched text carries an A$/AUD marker next to the amount.
-- Live effect for AU, NZ and CA: none expected. S1-Data-Gaps' live read (admin #1372, 28 Nov 16:10) found 0 active fees with a null currency
-- or a currency different from the provider country's default; AU, NZ and CA providers resolve to AUD, NZD and CAD as before.
-- Each function is edited from its live definition: every marker must be found exactly once, otherwise the migration stops and nothing changes.
-- Markers were checked against supabase/live-capture/baseline/schema.sql (captured 27 Nov 2026 03:21 UTC; no later migration on main
-- redefines these functions). The rolled-back rehearsal confirms them against live.
-- G1: no job. G2: no operational value (currency codes come from ref data). G3: none of these is the consumer API. Nothing dropped or deleted.
-- Replaces: the fixed 'AUD' currency in security.fee_rule_run_v1, security.provider_rule_admit_v1 and security.provider_basis_rule_admit_v1;
--   the AUD default in public.svc_coursefacts_apply_record; the NZ/CA/else-AUD map in security.adapter_overwrite_v1; the AUD/NZD/CAD
--   allowlist in security.layer4_tuition_apply_impl and security.layer3_tuition_admit_assumed_annual_v1.
-- Retires: nothing.

create or replace function security.fee_currency_resolve_v1(p_provider_id uuid, p_explicit text default null)
returns text
language sql
stable
security definer
set search_path to ''
as $f$
  select case
    when nullif(btrim(coalesce(p_explicit, '')), '') is not null then
      (select cy.code::text from ref.currencies cy where cy.code = upper(btrim(p_explicit)) and cy.status = 'active')
    else
      (select cy.code::text
         from catalogue.providers p
         join ref.countries k on k.id = p.country_id
         join ref.currencies cy on cy.code = k.default_currency_code and cy.status = 'active'
        where p.id = p_provider_id)
  end
$f$;

comment on function security.fee_currency_resolve_v1(uuid, text) is
  'CF-247 s1355 (28 Nov 2026): the currency a fee writer records. An explicit active ISO code (ref.currencies) wins; with none, the provider country''s default currency; otherwise null, and the caller holds the fee. Never AUD by default.';

revoke all on function security.fee_currency_resolve_v1(uuid, text) from public;
revoke all on function security.fee_currency_resolve_v1(uuid, text) from anon, authenticated;
grant execute on function security.fee_currency_resolve_v1(uuid, text) to service_role;

-- security.fee_rule_run_v1: 5 edit(s)
do $e$
declare d text := pg_get_functiondef('security.fee_rule_run_v1(bigint, boolean, uuid)'::regprocedure);
begin
  if (length(d) - length(replace(d, $o1$v_courses uuid[] := '{}'; v_op bigint;$o1$, ''))) / length($o1$v_courses uuid[] := '{}'; v_op bigint;$o1$) <> 1 then raise exception 'pre-check: security.fee_rule_run_v1 edit 1 marker is not found exactly once'; end if;
  d := replace(d, $o1$v_courses uuid[] := '{}'; v_op bigint;$o1$, $n1$v_courses uuid[] := '{}'; v_op bigint; v_cur text; n_cur int := 0;$n1$);
  if (length(d) - length(replace(d, $o2$    if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = m.course_id and l.field = 'tuition') then n_locked := n_locked + 1; continue; end if;
$o2$, ''))) / length($o2$    if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = m.course_id and l.field = 'tuition') then n_locked := n_locked + 1; continue; end if;
$o2$) <> 1 then raise exception 'pre-check: security.fee_rule_run_v1 edit 2 marker is not found exactly once'; end if;
  d := replace(d, $o2$    if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = m.course_id and l.field = 'tuition') then n_locked := n_locked + 1; continue; end if;
$o2$, $n2$    if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = m.course_id and l.field = 'tuition') then n_locked := n_locked + 1; continue; end if;
    -- s1355: currency from the evidence (an explicit A$/AUD marker) or the provider country; unknown is held, never AUD by default
    v_cur := security.fee_currency_resolve_v1(r.provider_id, case when m.matched_text ~* '(^|[^a-z])(aud([^a-z]|$)|a\s*\$)' then 'AUD' end);
    if v_cur is null then n_cur := n_cur + 1; continue; end if;
$n2$);
  if (length(d) - length(replace(d, $o3$m.amount, 'AUD', r.basis,$o3$, ''))) / length($o3$m.amount, 'AUD', r.basis,$o3$) <> 1 then raise exception 'pre-check: security.fee_rule_run_v1 edit 3 marker is not found exactly once'; end if;
  d := replace(d, $o3$m.amount, 'AUD', r.basis,$o3$, $n3$m.amount, v_cur, r.basis,$n3$);
  if (length(d) - length(replace(d, $o4$'entered_by_hand', n_locked), 'CF-CHG-20260915-247');$o4$, ''))) / length($o4$'entered_by_hand', n_locked), 'CF-CHG-20260915-247');$o4$) <> 1 then raise exception 'pre-check: security.fee_rule_run_v1 edit 4 marker is not found exactly once'; end if;
  d := replace(d, $o4$'entered_by_hand', n_locked), 'CF-CHG-20260915-247');$o4$, $n4$'entered_by_hand', n_locked, 'currency_unknown', n_cur), 'CF-CHG-20260915-247');$n4$);
  if (length(d) - length(replace(d, $o5$'entered_by_hand', n_locked);
end$o5$, ''))) / length($o5$'entered_by_hand', n_locked);
end$o5$) <> 1 then raise exception 'pre-check: security.fee_rule_run_v1 edit 5 marker is not found exactly once'; end if;
  d := replace(d, $o5$'entered_by_hand', n_locked);
end$o5$, $n5$'entered_by_hand', n_locked, 'currency_unknown', n_cur);
end$n5$);
  execute d;
end $e$;

-- security.provider_rule_admit_v1: 4 edit(s)
do $e$
declare d text := pg_get_functiondef('security.provider_rule_admit_v1(boolean, integer)'::regprocedure);
begin
  if (length(d) - length(replace(d, $o1$v_source uuid; v_review uuid;
begin$o1$, ''))) / length($o1$v_source uuid; v_review uuid;
begin$o1$) <> 1 then raise exception 'pre-check: security.provider_rule_admit_v1 edit 1 marker is not found exactly once'; end if;
  d := replace(d, $o1$v_source uuid; v_review uuid;
begin$o1$, $n1$v_source uuid; v_review uuid; v_prov uuid; v_cur text;
begin$n1$);
  if (length(d) - length(replace(d, $o2$  select jsonb_object_agg(outcome,n) into v_summary$o2$, ''))) / length($o2$  select jsonb_object_agg(outcome,n) into v_summary$o2$) <> 1 then raise exception 'pre-check: security.provider_rule_admit_v1 edit 2 marker is not found exactly once'; end if;
  d := replace(d, $o2$  select jsonb_object_agg(outcome,n) into v_summary$o2$, $n2$  -- s1355: an admissible amount whose currency is not known (no explicit A$/AUD marker and no provider-country currency) is held, never AUD by default
  update _pra p set outcome = 'currency not known (held)'
  where p.outcome in ('admit','admit (fee explanation)')
    and security.fee_currency_resolve_v1((select c.provider_id from catalogue.courses c where c.id = p.course_id), case when p.matched ~* '(^|[^a-z])(aud([^a-z]|$)|a\s*\$)' then 'AUD' end) is null;

  select jsonb_object_agg(outcome,n) into v_summary$n2$);
  if (length(d) - length(replace(d, $o3$      select course_code into v_code from catalogue.courses where id=r.course_id;
      select source_id into v_source from pipeline.evidence_artifacts where id=r.evidence_id;
      if v_code is null or v_source is null then continue; end if;$o3$, ''))) / length($o3$      select course_code into v_code from catalogue.courses where id=r.course_id;
      select source_id into v_source from pipeline.evidence_artifacts where id=r.evidence_id;
      if v_code is null or v_source is null then continue; end if;$o3$) <> 1 then raise exception 'pre-check: security.provider_rule_admit_v1 edit 3 marker is not found exactly once'; end if;
  d := replace(d, $o3$      select course_code into v_code from catalogue.courses where id=r.course_id;
      select source_id into v_source from pipeline.evidence_artifacts where id=r.evidence_id;
      if v_code is null or v_source is null then continue; end if;$o3$, $n3$      select course_code, provider_id into v_code, v_prov from catalogue.courses where id=r.course_id;
      select source_id into v_source from pipeline.evidence_artifacts where id=r.evidence_id;
      v_cur := security.fee_currency_resolve_v1(v_prov, case when r.matched ~* '(^|[^a-z])(aud([^a-z]|$)|a\s*\$)' then 'AUD' end);  -- s1355
      if v_code is null or v_source is null or v_cur is null then continue; end if;$n3$);
  if (length(d) - length(replace(d, $o4$r.amount,'AUD',r.basis,$o4$, ''))) / length($o4$r.amount,'AUD',r.basis,$o4$) <> 1 then raise exception 'pre-check: security.provider_rule_admit_v1 edit 4 marker is not found exactly once'; end if;
  d := replace(d, $o4$r.amount,'AUD',r.basis,$o4$, $n4$r.amount,v_cur,r.basis,$n4$);
  execute d;
end $e$;

-- security.provider_basis_rule_admit_v1: 5 edit(s)
do $e$
declare d text := pg_get_functiondef('security.provider_basis_rule_admit_v1(boolean, integer)'::regprocedure);
begin
  if (length(d) - length(replace(d, $o1$v_samples jsonb:='[]'::jsonb; v_amt_re text;$o1$, ''))) / length($o1$v_samples jsonb:='[]'::jsonb; v_amt_re text;$o1$) <> 1 then raise exception 'pre-check: security.provider_basis_rule_admit_v1 edit 1 marker is not found exactly once'; end if;
  d := replace(d, $o1$v_samples jsonb:='[]'::jsonb; v_amt_re text;$o1$, $n1$v_samples jsonb:='[]'::jsonb; v_amt_re text; v_cur text; v_cur_unknown int:=0;$n1$);
  if (length(d) - length(replace(d, $o2$    select w.id wid, w.entity_id course_id,$o2$, ''))) / length($o2$    select w.id wid, w.entity_id course_id,$o2$) <> 1 then raise exception 'pre-check: security.provider_basis_rule_admit_v1 edit 2 marker is not found exactly once'; end if;
  d := replace(d, $o2$    select w.id wid, w.entity_id course_id,$o2$, $n2$    select w.id wid, w.entity_id course_id, c.provider_id,$n2$);
  if (length(d) - length(replace(d, $o3$    if v_basis is null then v_nomatch:=v_nomatch+1; continue; end if;
$o3$, ''))) / length($o3$    if v_basis is null then v_nomatch:=v_nomatch+1; continue; end if;
$o3$) <> 1 then raise exception 'pre-check: security.provider_basis_rule_admit_v1 edit 3 marker is not found exactly once'; end if;
  d := replace(d, $o3$    if v_basis is null then v_nomatch:=v_nomatch+1; continue; end if;
$o3$, $n3$    if v_basis is null then v_nomatch:=v_nomatch+1; continue; end if;
    -- s1355: currency from the evidence (an explicit A$/AUD marker) or the provider country; unknown is held, never AUD by default
    v_cur:=security.fee_currency_resolve_v1(r.provider_id, case when v_text ~* '(^|[^a-z])(aud([^a-z]|$)|a\s*\$)' then 'AUD' end);
    if v_cur is null then v_cur_unknown:=v_cur_unknown+1; continue; end if;
$n3$);
  if (length(d) - length(replace(d, $o4$r.amount,'AUD',v_basis,$o4$, ''))) / length($o4$r.amount,'AUD',v_basis,$o4$) <> 1 then raise exception 'pre-check: security.provider_basis_rule_admit_v1 edit 4 marker is not found exactly once'; end if;
  d := replace(d, $o4$r.amount,'AUD',v_basis,$o4$, $n4$r.amount,v_cur,v_basis,$n4$);
  if (length(d) - length(replace(d, $o5$'not_matched',v_nomatch,'samples',v_samples);$o5$, ''))) / length($o5$'not_matched',v_nomatch,'samples',v_samples);$o5$) <> 1 then raise exception 'pre-check: security.provider_basis_rule_admit_v1 edit 5 marker is not found exactly once'; end if;
  d := replace(d, $o5$'not_matched',v_nomatch,'samples',v_samples);$o5$, $n5$'not_matched',v_nomatch,'currency_unknown',v_cur_unknown,'samples',v_samples);$n5$);
  execute d;
end $e$;

-- public.svc_coursefacts_apply_record: 2 edit(s)
do $e$
declare d text := pg_get_functiondef('public.svc_coursefacts_apply_record(uuid, uuid, text, text, text, text, text, jsonb, boolean)'::regprocedure);
begin
  if (length(d) - length(replace(d, $o1$v_currency:=coalesce(nullif(btrim(p_payload->>'currency_code'),''),'AUD');$o1$, ''))) / length($o1$v_currency:=coalesce(nullif(btrim(p_payload->>'currency_code'),''),'AUD');$o1$) <> 1 then raise exception 'pre-check: public.svc_coursefacts_apply_record edit 1 marker is not found exactly once'; end if;
  d := replace(d, $o1$v_currency:=coalesce(nullif(btrim(p_payload->>'currency_code'),''),'AUD');$o1$, $n1$v_currency:=security.fee_currency_resolve_v1(v_provider,p_payload->>'currency_code');$n1$);
  if (length(d) - length(replace(d, $o2$if not exists(select 1 from ref.currencies where code=v_currency) then raise exception 'currency not seeded: %',v_currency;end if;$o2$, ''))) / length($o2$if not exists(select 1 from ref.currencies where code=v_currency) then raise exception 'currency not seeded: %',v_currency;end if;$o2$) <> 1 then raise exception 'pre-check: public.svc_coursefacts_apply_record edit 2 marker is not found exactly once'; end if;
  d := replace(d, $o2$if not exists(select 1 from ref.currencies where code=v_currency) then raise exception 'currency not seeded: %',v_currency;end if;$o2$, $n2$if v_currency is null then raise exception 'currency not known: % (not an active ISO currency code, and the provider country has no default currency)',coalesce(nullif(btrim(p_payload->>'currency_code'),''),'none given');end if;$n2$);
  execute d;
end $e$;

-- security.layer4_tuition_apply_impl: 1 edit(s)
do $e$
declare d text := pg_get_functiondef('security.layer4_tuition_apply_impl(uuid, uuid, jsonb, text)'::regprocedure);
begin
  if (length(d) - length(replace(d, $o1$  if v_cur not in ('AUD','NZD','CAD') then raise exception 'currency must be AUD, NZD or CAD'; end if;$o1$, ''))) / length($o1$  if v_cur not in ('AUD','NZD','CAD') then raise exception 'currency must be AUD, NZD or CAD'; end if;$o1$) <> 1 then raise exception 'pre-check: security.layer4_tuition_apply_impl edit 1 marker is not found exactly once'; end if;
  d := replace(d, $o1$  if v_cur not in ('AUD','NZD','CAD') then raise exception 'currency must be AUD, NZD or CAD'; end if;$o1$, $n1$  -- s1355: an explicit active ISO currency code, else the provider country's currency; an unknown currency is refused (it was written as null before)
  v_cur := security.fee_currency_resolve_v1((select c.provider_id from catalogue.courses c where c.id = v_item.entity_id), v_cur);
  if v_cur is null then raise exception 'currency must be an active ISO currency code (none was given and the provider country has no default currency)'; end if;$n1$);
  execute d;
end $e$;

-- security.layer3_tuition_admit_assumed_annual_v1: 1 edit(s)
do $e$
declare d text := pg_get_functiondef('security.layer3_tuition_admit_assumed_annual_v1(integer)'::regprocedure);
begin
  if (length(d) - length(replace(d, $o1$or v_cur not in ('AUD','NZD','CAD')$o1$, ''))) / length($o1$or v_cur not in ('AUD','NZD','CAD')$o1$) <> 1 then raise exception 'pre-check: security.layer3_tuition_admit_assumed_annual_v1 edit 1 marker is not found exactly once'; end if;
  d := replace(d, $o1$or v_cur not in ('AUD','NZD','CAD')$o1$, $n1$or v_cur is null or not exists (select 1 from ref.currencies cy where cy.code = v_cur and cy.status = 'active')  /* s1355: any active ISO code; none is held */$n1$);
  execute d;
end $e$;

-- security.adapter_overwrite_v1: 2 edit(s)
do $e$
declare d text := pg_get_functiondef('security.adapter_overwrite_v1(integer)'::regprocedure);
begin
  if (length(d) - length(replace(d, $o1$    v_cur := coalesce(nullif(r.c->'fee'->>'currency', ''), case security.coverage_country(r.provider_id) when 'NZ' then 'NZD' when 'CA' then 'CAD' else 'AUD' end);$o1$, ''))) / length($o1$    v_cur := coalesce(nullif(r.c->'fee'->>'currency', ''), case security.coverage_country(r.provider_id) when 'NZ' then 'NZD' when 'CA' then 'CAD' else 'AUD' end);$o1$) <> 1 then raise exception 'pre-check: security.adapter_overwrite_v1 edit 1 marker is not found exactly once'; end if;
  d := replace(d, $o1$    v_cur := coalesce(nullif(r.c->'fee'->>'currency', ''), case security.coverage_country(r.provider_id) when 'NZ' then 'NZD' when 'CA' then 'CAD' else 'AUD' end);$o1$, $n1$    v_cur := security.fee_currency_resolve_v1(r.provider_id, r.c->'fee'->>'currency');  -- s1355: the read currency, else the provider country's; no fixed country map, no AUD default$n1$);
  if (length(d) - length(replace(d, $o2$    if r.c->>'fee_by' = 'adapter' and v_fee is not null and v_fee between$o2$, ''))) / length($o2$    if r.c->>'fee_by' = 'adapter' and v_fee is not null and v_fee between$o2$) <> 1 then raise exception 'pre-check: security.adapter_overwrite_v1 edit 2 marker is not found exactly once'; end if;
  d := replace(d, $o2$    if r.c->>'fee_by' = 'adapter' and v_fee is not null and v_fee between$o2$, $n2$    if r.c->>'fee_by' = 'adapter' and v_fee is not null and v_cur is not null and v_fee between$n2$);
  execute d;
end $e$;
