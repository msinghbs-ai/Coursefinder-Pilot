-- CF-247 Scholarships: Australia, New Zealand and Canada only for now; a ready plan that triggers as more
-- countries join. Platform Admin (9 Oct 2026): "Let only target au, nz, can at the moment for scholarships,
-- more countries will be joining in later make sure plan are in place to trigger as more countries come along."
--
-- 1. Scope: scholarships run for AU, NZ and CA only. The country switch (ref.countries.scholarship_ingestion_enabled)
--    was also on for DE, GB, IE and US, which have no courses; it is switched off for them (logged).
-- 2. scholarship.country_onboarding: one row per country: status (enabled / watch), the country's domestic-student
--    wording (so audience is read correctly there), the government registers to build, and notes.
-- 3. Planned government registers for the first likely countries (GB, US), so the work is listed before it is needed.
-- 4. security.scholarship_country_readiness_v1(): per country - courses, providers, universities, switch, wording,
--    nationality term, registers, discovery queue - and what is missing before it can be switched on.
-- 5. Daily job scholarship-country-watch (06:13 Melbourne): a country with courses but scholarships off, or switched
--    on with something missing, raises a platform issue (scholarship_country:<code>) with the missing steps; the
--    issue resolves itself when the country is ready and switched on, or has no courses.
-- 6. public.admin_scholarship_country(code, on, reason): Platform Admin switches a country on (only when ready) or
--    off; logged; switching on queues its universities for scholarship discovery straight away.
-- 7. No country code is hard-wired any more where a new country needs it (md5-guarded patches):
--    security.scholarship_university reads the switch for every country other than Australia (which keeps its own
--    university test); the audience reader uses the country's domestic wording from country_onboarding for any
--    country other than AU, NZ and CA. Behaviour for AU, NZ and CA is unchanged.
-- Nothing is published or deleted.

create table if not exists scholarship.country_onboarding (
  country_code char(2) primary key,
  status text not null check (status in ('enabled','watch')),
  domestic_terms text,
  government_registers text[] not null default '{}',
  notes text,
  decided_by uuid,
  decided_at timestamptz,
  reason text,
  updated_at timestamptz not null default now()
);
alter table scholarship.country_onboarding enable row level security;
revoke all on scholarship.country_onboarding from public, anon, authenticated;

insert into scholarship.country_onboarding(country_code, status, domestic_terms, government_registers, notes) values
 ('AU','enabled',null,array['au_study_australia','au_dfat_australia_awards'],'Live: provider pages, Study Australia index, Australia Awards. Domestic wording built into the audience reader.'),
 ('NZ','enabled',null,array['nz_mfat_manaaki'],'Live: provider pages (universities), Manaaki. Domestic wording built into the audience reader.'),
 ('CA','enabled',null,array['ca_gac_study_in_canada'],'Live: provider pages (universities). Government register held: EduCanada robots.txt blocks automated readers. Domestic wording built into the audience reader.'),
 ('GB','watch','domestic students?|home students?|uk students?|british citizens?|uk citizens?|settled status|pre-settled status|indefinite leave to remain|home fee status|uk residents?|student finance england','{uk_fcdo_chevening,uk_cscuk_commonwealth}','Joins when UK courses are in the catalogue. Government awards: Chevening (FCDO), Commonwealth Scholarships (CSC UK).'),
 ('US','watch','domestic students?|us citizens?|u\.s\. citizens?|american citizens?|permanent residents? of the united states|green card holders?|in-state students?|state residents?|fafsa|pell grant','{us_fulbright_foreign_student}','Joins when US courses are in the catalogue. Government award: Fulbright Foreign Student Program.'),
 ('IE','watch','domestic students?|irish citizens?|eu students?|eea students?|home students?|irish residents?|susi grant|free fees','{}','Joins when Irish courses are in the catalogue. Government awards to be researched (Government of Ireland International Education Scholarships).'),
 ('DE','watch','domestic students?|german citizens?|eu students?|bafög|bafoeg|german residents?','{}','Joins when German courses are in the catalogue. Government awards to be researched (DAAD).')
on conflict (country_code) do nothing;

insert into scholarship.registers(code, country_code, name, url, role, source_id, reader, status, notes) values
 ('uk_fcdo_chevening','GB','Chevening Scholarships (FCDO)','https://www.chevening.org/scholarships/','record',null,null,'planned','Built when the United Kingdom joins (country_onboarding GB).'),
 ('uk_cscuk_commonwealth','GB','Commonwealth Scholarships (CSC UK)','https://cscuk.fcdo.gov.uk/scholarships/','record',null,null,'planned','Built when the United Kingdom joins (country_onboarding GB).'),
 ('us_fulbright_foreign_student','US','Fulbright Foreign Student Program','https://foreign.fulbrightonline.org/','record',null,null,'planned','Built when the United States joins (country_onboarding US).')
on conflict (code) do nothing;

-- 1. scope: switch off the countries without courses (logged)
insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'scholarships', 'scholarship_country_off', c.iso_alpha2,
       jsonb_build_object('reason','Platform Admin 9 Oct 2026: scholarships for AU, NZ and CA only for now; switched on per country when it joins.',
                          'active_courses', (select count(*) from catalogue.courses co join catalogue.providers p on p.id = co.provider_id where p.country_id = c.id and co.lifecycle_status = 'active')),
       '63ba56cb-48d4-4169-98c2-7c4d1f72925b'
  from ref.countries c where c.scholarship_ingestion_enabled and c.iso_alpha2 not in ('AU','NZ','CA');
update ref.countries set scholarship_ingestion_enabled = false where scholarship_ingestion_enabled and iso_alpha2 not in ('AU','NZ','CA');

-- 7. patches (only if each function is exactly the expected version; behaviour for AU, NZ, CA unchanged)
do $patch$
declare d text; n int;
begin
  d := pg_get_functiondef('security.scholarship_university'::regproc);
  if md5(d) <> '643f0224c501380348763c42cc466473' then raise exception 'scholarship_university changed; refusing to patch'; end if;
  n := (length(d) - length(replace(d, $a$c.iso_alpha2 in ('NZ', 'CA') and c.scholarship_ingestion_enabled$a$, ''))) / length($a$c.iso_alpha2 in ('NZ', 'CA') and c.scholarship_ingestion_enabled$a$);
  if n <> 1 then raise exception 'scholarship_university anchor found % times', n; end if;
  execute replace(d, $a$c.iso_alpha2 in ('NZ', 'CA') and c.scholarship_ingestion_enabled$a$, $a$c.iso_alpha2 <> 'AU' and c.scholarship_ingestion_enabled$a$);

  d := pg_get_functiondef('security.scholarship_audience_read_v1'::regproc);
  if md5(d) <> '6c85cb74ea3b00bc45e385f6c278dc08' then raise exception 'scholarship_audience_read_v1 changed; refusing to patch'; end if;
  n := (length(d) - length(replace(d, $a$case t.cc when 'NZ' then c_dom_nz when 'CA' then c_dom_ca else c_dom end$a$, ''))) / length($a$case t.cc when 'NZ' then c_dom_nz when 'CA' then c_dom_ca else c_dom end$a$);
  if n <> 1 then raise exception 'audience anchor found % times', n; end if;
  execute replace(d, $a$case t.cc when 'NZ' then c_dom_nz when 'CA' then c_dom_ca else c_dom end$a$,
    $a$case t.cc when 'NZ' then c_dom_nz when 'CA' then c_dom_ca when 'AU' then c_dom else coalesce((select '\m(' || o.domestic_terms || ')\M' from scholarship.country_onboarding o where o.country_code = t.cc and coalesce(o.domestic_terms, '') <> ''), c_dom) end$a$);
end $patch$;

-- 4. readiness per country
create or replace function security.scholarship_country_readiness_v1()
returns table(country_code text, country text, active_courses bigint, providers bigint, universities bigint, switched_on boolean,
              status text, domestic_terms boolean, nationality_term boolean, registers_live int, registers_planned int,
              discovery_queued bigint, ready boolean, missing text[])
language sql stable security definer set search_path = '' as $$
  with c as (
    select k.id, k.iso_alpha2::text cc, k.name, k.scholarship_ingestion_enabled sw,
           (select count(*) from catalogue.courses co join catalogue.providers p on p.id = co.provider_id where p.country_id = k.id and co.lifecycle_status = 'active') courses,
           (select count(*) from catalogue.providers p where p.country_id = k.id and p.lifecycle_status = 'active') providers,
           o.status, o.domestic_terms, o.government_registers
      from ref.countries k left join scholarship.country_onboarding o on o.country_code = k.iso_alpha2
     where k.scholarship_ingestion_enabled or o.country_code is not null
        or exists (select 1 from catalogue.providers p join catalogue.courses co on co.provider_id = p.id where p.country_id = k.id and co.lifecycle_status = 'active'))
  select c.cc, c.name, c.courses, c.providers,
         (select count(*) from catalogue.providers p where p.country_id = c.id and p.lifecycle_status = 'active'
             and (security.australian_university(p.id) or jsonb_array_length(coalesce(security.provider_university_groups(p.id), '[]')) > 0
                  or (p.canonical_name ~* '\m(university|université|universite)\M' and p.canonical_name !~* '(college|pathways?|language cent|senior|theology|divinity)'))) unis,
         c.sw, coalesce(c.status, 'not listed'),
         c.cc in ('AU','NZ','CA') or coalesce(c.domestic_terms, '') <> '',
         c.cc = 'AU' or exists (select 1 from ref.nationality_terms x where x.code = c.cc),
         (select count(*)::int from scholarship.registers r where r.country_code = c.cc and r.status = 'live'),
         (select count(*)::int from scholarship.registers r where r.country_code = c.cc and r.status = 'planned'),
         (select count(*) from pipeline.scholarship_discovery_providers d join catalogue.providers p on p.id = d.provider_id where p.country_id = c.id),
         x.missing = '{}', x.missing
    from c cross join lateral (select array_remove(array[
         case when c.courses = 0 then 'no active courses in the catalogue yet' end,
         case when c.status is null then 'no onboarding entry (scholarship.country_onboarding)' end,
         case when not (c.cc in ('AU','NZ','CA') or coalesce(c.domestic_terms, '') <> '') then 'no domestic-student wording for the audience reader' end,
         case when not (c.cc = 'AU' or exists (select 1 from ref.nationality_terms x where x.code = c.cc)) then 'no nationality term for the country' end,
         case when c.courses > 0 and not exists (select 1 from catalogue.providers p where p.country_id = c.id and p.lifecycle_status = 'active'
                and (security.australian_university(p.id) or jsonb_array_length(coalesce(security.provider_university_groups(p.id), '[]')) > 0
                     or (p.canonical_name ~* '\m(university|université|universite)\M' and p.canonical_name !~* '(college|pathways?|language cent|senior|theology|divinity)')))
              then 'no university providers recognised' end,
         case when c.sw and c.courses > 0 and not exists (select 1 from pipeline.scholarship_discovery_providers d join catalogue.providers p on p.id = d.provider_id where p.country_id = c.id)
              then 'switched on but no provider queued for scholarship discovery' end
       ], null) missing) x
   order by (c.courses > 0) desc, c.cc
$$;
revoke all on function security.scholarship_country_readiness_v1() from public, anon, authenticated;

-- 5. daily watch: raise or resolve one platform issue per country
create or replace function security.scholarship_country_watch_v1()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r record; v_raised int := 0; v_resolved int := 0; v_keys text[] := '{}';
begin
  for r in select * from security.scholarship_country_readiness_v1() where active_courses > 0 and (not switched_on or not ready) loop
    v_keys := v_keys || ('scholarship_country:' || r.country_code);
    insert into pipeline.platform_issues as i (check_key, severity, area, title, detail)
    values ('scholarship_country:' || r.country_code, 'warning', 'scholarships',
            left(case when not r.switched_on then r.country || ' has ' || r.active_courses || ' courses but scholarships are not switched on'
                      else r.country || ': scholarships switched on but not ready' end, 300),
            jsonb_build_object('country', r.country_code, 'active_courses', r.active_courses, 'universities', r.universities,
                               'switched_on', r.switched_on, 'missing', to_jsonb(r.missing), 'registers_planned', r.registers_planned,
                               'next_steps', jsonb_build_array(
                                 'Check the domestic-student wording and government registers in scholarship.country_onboarding',
                                 'Build the planned government registers (Layer 1 record registers) for the country',
                                 'Switch the country on: admin_scholarship_country(code, true, reason) - queues its universities for discovery',
                                 'Check reporting views that list countries (data quality, Zoho reference bundle)')))
    on conflict (check_key) where resolved_at is null do update set title = excluded.title, detail = excluded.detail, last_seen = now(), occurrences = i.occurrences + 1;
    v_raised := v_raised + 1;
  end loop;
  update pipeline.platform_issues set resolved_at = now()
   where resolved_at is null and check_key like 'scholarship_country:%' and not (check_key = any(v_keys));
  get diagnostics v_resolved = row_count;
  return jsonb_build_object('raised_or_updated', v_raised, 'resolved', v_resolved, 'at', now());
end $$;
revoke all on function security.scholarship_country_watch_v1() from public, anon, authenticated;

-- 6. switch a country on or off (Platform Admin)
create or replace function public.admin_scholarship_country(p_country_code text, p_on boolean, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r record; v_refill jsonb; v_cc text := upper(btrim(coalesce(p_country_code, '')));
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  select * into r from security.scholarship_country_readiness_v1() x where x.country_code = v_cc;
  if r.country_code is null then raise exception 'country % has no onboarding entry, courses or switch', v_cc; end if;
  if p_on and not r.ready then raise exception 'country % is not ready: %', v_cc, array_to_string(r.missing, '; '); end if;
  update ref.countries set scholarship_ingestion_enabled = p_on where iso_alpha2 = v_cc;
  update scholarship.country_onboarding set status = case when p_on then 'enabled' else 'watch' end, decided_by = auth.uid(), decided_at = now(),
         reason = left(p_reason, 500), updated_at = now() where country_code = v_cc;
  if p_on then v_refill := security.scholarship_discovery_refill_v1(30 + coalesce(r.universities, 0)::int); end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('scholarships', case when p_on then 'scholarship_country_on' else 'scholarship_country_off' end, v_cc,
          jsonb_build_object('reason', left(p_reason, 500), 'readiness', to_jsonb(r), 'discovery', v_refill), auth.uid());
  perform security.scholarship_country_watch_v1();
  return jsonb_build_object('ok', true, 'country', v_cc, 'switched_on', p_on, 'discovery', v_refill);
end $$;
revoke all on function public.admin_scholarship_country(text, boolean, text) from public, anon;
grant execute on function public.admin_scholarship_country(text, boolean, text) to authenticated;

-- read for admins (rank 5 and above)
create or replace function public.admin_scholarship_countries()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 5 then raise exception 'insufficient role' using errcode = '42501'; end if;
  return coalesce((select jsonb_agg(to_jsonb(x)) from security.scholarship_country_readiness_v1() x), '[]'::jsonb);
end $$;
revoke all on function public.admin_scholarship_countries() from public, anon;
grant execute on function public.admin_scholarship_countries() to authenticated;

select cron.schedule('scholarship-country-watch', '13 19 * * *', 'select security.scholarship_country_watch_v1()');
