-- CF-247 Decision 253 (4 Oct 2026): the country code is char(2) in ref.countries. The target list returns it as text.
-- No text value in this file contains a semicolon.

create or replace function security.firecrawl_targets_v1() returns table (provider_id uuid, country text, name text, courses int, rule_match boolean, included boolean, override_reason text, domain text)
language plpgsql stable security definer set search_path = '' as $f$
declare v_countries text[]; v_pat text; v_excl text; v_regs text[]; v_min jsonb := '{}'::jsonb; x text;
begin
  select coalesce(array_agg(upper(btrim(e))), '{}') into v_countries from jsonb_array_elements_text(coalesce(security.firecrawl_setting('target_countries'), '[]'::jsonb)) e;
  v_pat := coalesce(security.firecrawl_setting('target_name_pattern') #>> '{}', '(^|[^a-z])universit(y|ies)([^a-z]|$)');
  v_excl := nullif(btrim(coalesce(security.firecrawl_setting('target_exclude_pattern') #>> '{}', '')), '');
  select coalesce(array_agg(lower(btrim(e))), '{}') into v_regs from jsonb_array_elements_text(coalesce(security.firecrawl_setting('target_registers'), '[]'::jsonb)) e;
  for x in select jsonb_array_elements_text(coalesce(security.firecrawl_setting('target_min_courses'), '[]'::jsonb)) loop
    if x ~ '^\s*[A-Za-z]{2}\s*:\s*[0-9]+\s*$' then v_min := v_min || jsonb_build_object(upper(btrim(split_part(x, ':', 1))), btrim(split_part(x, ':', 2))::int); end if;
  end loop;
  return query
  with cand as (
    select p.id, k.iso_alpha2::text cc, coalesce(p.display_name, p.canonical_name) nm, p.website, p.enrols_international,
           (select count(*)::int from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active') n,
           t.included ov, t.reason ovr
    from catalogue.providers p join ref.countries k on k.id = p.country_id
    left join pipeline.firecrawl_targets t on t.provider_id = p.id
    where t.provider_id is not null or (k.iso_alpha2 = any(v_countries) and coalesce(p.display_name, p.canonical_name) ~* v_pat)
  ), ruled as (
    select c.*, (c.cc = any(v_countries) and c.nm ~* v_pat and (v_excl is null or c.nm !~* v_excl)
                 and c.n >= coalesce((v_min->>c.cc)::int, 0)
                 and (c.enrols_international is true or exists (select 1 from catalogue.provider_registrations r where r.provider_id = c.id and lower(r.registration_scheme) = any(v_regs)))) rm
    from cand c
  )
  select r.id, r.cc, r.nm, r.n, r.rm, coalesce(r.ov, r.rm), r.ovr,
         coalesce(nullif(regexp_replace(lower(substring(r.website from '^(?:https?://)?([^/?#]+)')), '^www\.', ''), ''),
                  (select regexp_replace(lower(substring(pg.url from '^https?://([^/?#]+)')), '^www\.', '') h from pipeline.coverage_course_pages pg
                    where pg.provider_id = r.id and pg.status = 'bound' and pg.read_status = 'read' group by 1 order by count(*) desc limit 1))
  from ruled r;
end $f$;
revoke all on function security.firecrawl_targets_v1() from public, anon, authenticated;
