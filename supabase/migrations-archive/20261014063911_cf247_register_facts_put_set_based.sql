-- CF-247 v2.15.276 (14 Oct 2026) Decision 258, fix found on the first live apply: svc_provider_register_facts_put looked up each
-- register code one at a time (1,545 CRICOS Institutions codes) and passed the 8 second statement limit of the API role.
-- It now matches every code in one statement (CRICOS registrations, else the provider stable key) and writes the facts in one
-- upsert. Same arguments and result keys. md5-checked before. Nothing is dropped or deleted.
do $d$
begin
  if md5(pg_get_functiondef('public.svc_provider_register_facts_put(uuid,uuid,text,jsonb)'::regprocedure)) <> 'd1b4e3b2b1689f13a211703475f2b7a2' then raise exception 'svc_provider_register_facts_put changed since the check'; end if;
end $d$;

create or replace function public.svc_provider_register_facts_put(p_source_id uuid, p_evidence_id uuid, p_scheme text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_out jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with src as (
    select ord, upper(btrim(c)) code, r->'facts' facts
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) with ordinality x(r, ord)
    cross join lateral jsonb_array_elements_text(coalesce(r->'codes', '[]'::jsonb)) c
    where btrim(c) <> ''
  ), reg as (
    select distinct on (upper(pr.registration_code)) upper(pr.registration_code) code, pr.provider_id
    from catalogue.provider_registrations pr
    where lower(pr.registration_scheme) = lower(p_scheme)
    order by upper(pr.registration_code), pr.checked_at desc nulls last
  ), m as (
    select s.ord, s.code, s.facts, coalesce(reg.provider_id, p.id) provider_id
    from src s
    left join reg on reg.code = s.code
    left join catalogue.providers p on p.stable_key = 'provider:' || lower(p_scheme) || ':' || lower(s.code)
  ), f as (
    select distinct on (m.provider_id, e.key) m.provider_id, e.key fact_code, nullif(btrim(e.value), '') fact_value
    from m cross join lateral jsonb_each_text(coalesce(m.facts, '{}'::jsonb)) e
    where m.provider_id is not null
    order by m.provider_id, e.key, m.ord desc
  ), w as (
    insert into catalogue.provider_register_facts (provider_id, fact_code, value, source_id, evidence_id, observed_at)
    select provider_id, fact_code, fact_value, p_source_id, p_evidence_id, now() from f
    on conflict (provider_id, fact_code) do update set value = excluded.value, source_id = excluded.source_id,
      evidence_id = coalesce(excluded.evidence_id, catalogue.provider_register_facts.evidence_id), observed_at = now()
    returning 1
  )
  select jsonb_build_object(
    'rows', jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    'providers_matched', (select count(distinct provider_id) from m where provider_id is not null),
    'codes_unmatched', (select count(*) from m where provider_id is null),
    'facts_written', (select count(*) from w))
  into v_out;
  return v_out;
end $$;
revoke all on function public.svc_provider_register_facts_put(uuid, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_provider_register_facts_put(uuid, uuid, text, jsonb) to service_role;
