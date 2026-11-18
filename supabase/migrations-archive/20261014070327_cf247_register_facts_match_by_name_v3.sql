-- CF-247 v2.15.276 (14 Oct 2026) Decision 258: NZQA name match, third pass (replaces 20261014070026, which passed the time limit). The NZQA provider search lists every site of a
-- provider as its own row, under the provider name or a trading name, and some names lose their macron as a question mark.
-- The first pass needed exactly one provider per name and matched 195 of 415. Now:
--  1. Names are compared in lower case, macron vowels as plain vowels, punctuation as spaces, and a question mark in either name
--     stands for any one letter.
--  2. A listed name is used only when every row with that name carries the same facts (the same organisation type), and it
--     then applies to every provider of the register with that name (for example the divisions of one institute).
--  3. A code that matches a registration or stable key is never matched by name.
-- The working sets are materialised so each name is normalised once (the first draft passed the 8 second limit).
-- md5-checked before. Nothing is dropped or deleted.
do $d$
begin
  if md5(pg_get_functiondef('public.svc_provider_register_facts_put(uuid,uuid,text,jsonb)'::regprocedure)) <> '7f33287ce26415d7bd5dafcc9798327e' then raise exception 'svc_provider_register_facts_put changed since the check'; end if;
end $d$;

create or replace function security.register_name_key_v1(p_name text)
returns text language sql immutable set search_path to '' as $$
  select nullif(btrim(regexp_replace(lower(translate(coalesce(p_name, ''), 'āēīōūĀĒĪŌŪ', 'aeiouaeiou')), '[^a-z0-9?]+', ' ', 'g')), '')
$$;

create or replace function public.svc_provider_register_facts_put(p_source_id uuid, p_evidence_id uuid, p_scheme text, p_rows jsonb)
returns jsonb language plpgsql security definer set search_path to '' as $$
declare v_out jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  with src as materialized (
    select ord, upper(btrim(c)) code, r->'facts' facts, security.register_name_key_v1(r->'names'->>0) name_key
    from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb)) with ordinality x(r, ord)
    cross join lateral jsonb_array_elements_text(coalesce(r->'codes', '[]'::jsonb)) c
    where btrim(c) <> ''
  ), reg as (
    select distinct on (upper(pr.registration_code)) upper(pr.registration_code) code, pr.provider_id
    from catalogue.provider_registrations pr
    where lower(pr.registration_scheme) = lower(p_scheme)
    order by upper(pr.registration_code), pr.checked_at desc nulls last
  ), m0 as (
    select s.ord, s.code, s.facts, s.name_key, coalesce(reg.provider_id, p.id) provider_id
    from src s
    left join reg on reg.code = s.code
    left join catalogue.providers p on p.stable_key = 'provider:' || lower(p_scheme) || ':' || lower(s.code)
  ), consistent as materialized (
    select name_key from src where name_key is not null group by 1 having count(distinct facts::text) = 1
  ), named as materialized (
    select p.id provider_id, security.register_name_key_v1(p.canonical_name) name_key
    from catalogue.providers p
    where p.stable_key like 'provider:' || lower(p_scheme) || ':%'
  ), m as materialized (
    select ord, code, facts, provider_id, false by_name from m0 where provider_id is not null
    union all
    select s.ord, s.code, s.facts, n.provider_id, true
    from m0 s
    join consistent k on k.name_key = s.name_key
    join named n on n.name_key = s.name_key
      or (strpos(s.name_key, '?') > 0 and n.name_key like replace(s.name_key, '?', '_'))
      or (strpos(n.name_key, '?') > 0 and s.name_key like replace(n.name_key, '?', '_'))
    where s.provider_id is null
  ), f as (
    select distinct on (m.provider_id, e.key) m.provider_id, e.key fact_code, nullif(btrim(e.value), '') fact_value
    from m cross join lateral jsonb_each_text(coalesce(m.facts, '{}'::jsonb)) e
    order by m.provider_id, e.key, m.by_name, m.ord desc
  ), w as (
    insert into catalogue.provider_register_facts (provider_id, fact_code, value, source_id, evidence_id, observed_at)
    select provider_id, fact_code, fact_value, p_source_id, p_evidence_id, now() from f
    on conflict (provider_id, fact_code) do update set value = excluded.value, source_id = excluded.source_id,
      evidence_id = coalesce(excluded.evidence_id, catalogue.provider_register_facts.evidence_id), observed_at = now()
    returning 1
  )
  select jsonb_build_object(
    'rows', jsonb_array_length(coalesce(p_rows, '[]'::jsonb)),
    'providers_matched', (select count(distinct provider_id) from m),
    'codes_unmatched', (select count(*) from m0 where provider_id is null and not exists (select 1 from m where m.code = m0.code)),
    'matched_by_name', (select count(distinct provider_id) from m where by_name),
    'facts_written', (select count(*) from w))
  into v_out;
  return v_out;
end $$;
revoke all on function public.svc_provider_register_facts_put(uuid, uuid, text, jsonb) from public, anon, authenticated;
grant execute on function public.svc_provider_register_facts_put(uuid, uuid, text, jsonb) to service_role;
revoke all on function security.register_name_key_v1(text) from public, anon, authenticated;
