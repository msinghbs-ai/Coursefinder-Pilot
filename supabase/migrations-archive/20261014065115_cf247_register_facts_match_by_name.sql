-- CF-247 v2.15.276 (14 Oct 2026) Decision 258: the NZQA provider search links each provider by an internal search number,
-- not its NZQA organisation number, so the first NZQA read matched none of 415. A row may now carry the register name
-- (names: [..]). A code that matches no registration or stable key is matched by that name, letters and digits only, among the
-- providers of the same register, and only when exactly one provider has that name. The result adds matched_by_name.
-- md5-checked before. Nothing is dropped or deleted.
do $d$
begin
  if md5(pg_get_functiondef('public.svc_provider_register_facts_put(uuid,uuid,text,jsonb)'::regprocedure)) <> '9d5275784d1f9f50bcd0b1c43deafb78' then raise exception 'svc_provider_register_facts_put changed since the check'; end if;
end $d$;

create or replace function public.svc_provider_register_facts_put(p_source_id uuid, p_evidence_id uuid, p_scheme text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_out jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with src as (
    select ord, upper(btrim(c)) code, r->'facts' facts,
      nullif(lower(btrim(regexp_replace(coalesce(r->'names'->>0, ''), '[^A-Za-z0-9]+', ' ', 'g'))), '') name_key
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) with ordinality x(r, ord)
    cross join lateral jsonb_array_elements_text(coalesce(r->'codes', '[]'::jsonb)) c
    where btrim(c) <> ''
  ), named as (
    select lower(btrim(regexp_replace(p.canonical_name, '[^A-Za-z0-9]+', ' ', 'g'))) name_key, min(p.id::text)::uuid provider_id
    from catalogue.providers p
    where p.stable_key like 'provider:' || lower(p_scheme) || ':%'
    group by 1 having count(*) = 1
  ), reg as (
    select distinct on (upper(pr.registration_code)) upper(pr.registration_code) code, pr.provider_id
    from catalogue.provider_registrations pr
    where lower(pr.registration_scheme) = lower(p_scheme)
    order by upper(pr.registration_code), pr.checked_at desc nulls last
  ), m as (
    select s.ord, s.code, s.facts, coalesce(reg.provider_id, p.id, nm.provider_id) provider_id, (reg.provider_id is null and p.id is null and nm.provider_id is not null) by_name
    from src s
    left join reg on reg.code = s.code
    left join catalogue.providers p on p.stable_key = 'provider:' || lower(p_scheme) || ':' || lower(s.code)
    left join named nm on nm.name_key = s.name_key
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
    'matched_by_name', (select count(*) from m where by_name),
    'facts_written', (select count(*) from w))
  into v_out;
  return v_out;
end $$;
revoke all on function public.svc_provider_register_facts_put(uuid, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_provider_register_facts_put(uuid, uuid, text, jsonb) to service_role;
