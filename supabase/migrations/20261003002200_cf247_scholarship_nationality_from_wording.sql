-- CF-247 (3 Oct 2026, 21:30 AEST). Decision 246. Scholarship plan step 3: who a scholarship is for by nationality is
-- read from the scholarship's own wording ("citizens of India", "Sri Lankan citizen", "students from South Asia"),
-- against a fixed list of country names, demonyms and regions, with the matched phrase kept as the basis. Australia is
-- never a nationality here (the study country), and for an Australian provider "New Zealand citizen" is the domestic
-- rule (Decision 212), not a nationality. A value set by hand is never changed. An empty list means the page names no
-- nationality: the scholarship is open to any nationality its audience allows. Hourly job scholarship-nationality.
create table if not exists ref.nationality_terms(
  code text primary key, names text not null, demonyms text not null default '', region boolean not null default false);
insert into ref.nationality_terms(code, names, demonyms, region)
select v.code, v.names, v.demonyms, v.code like 'R-%' from (values
  ('IN', 'India', 'Indian'), ('CN', 'China', 'Chinese'), ('NP', 'Nepal', 'Nepalese|Nepali'), ('PK', 'Pakistan', 'Pakistani'), ('BD', 'Bangladesh', 'Bangladeshi'), ('LK', 'Sri Lanka', 'Sri Lankan'),
  ('VN', 'Vietnam|Viet Nam', 'Vietnamese'), ('ID', 'Indonesia', 'Indonesian'), ('MY', 'Malaysia', 'Malaysian'), ('SG', 'Singapore', 'Singaporean'), ('TH', 'Thailand', 'Thai'), ('PH', 'Philippines', 'Filipino|Philippine'),
  ('KH', 'Cambodia', 'Cambodian'), ('LA', 'Laos|Lao PDR', 'Lao|Laotian'), ('MM', 'Myanmar|Burma', 'Burmese'), ('BN', 'Brunei', 'Bruneian'), ('TL', 'Timor-Leste|East Timor', 'Timorese'), ('MN', 'Mongolia', 'Mongolian'),
  ('JP', 'Japan', 'Japanese'), ('KR', 'South Korea|Korea', 'Korean'), ('TW', 'Taiwan', 'Taiwanese'), ('HK', 'Hong Kong', 'Hong Kong'), ('MO', 'Macau|Macao', 'Macanese'), ('BT', 'Bhutan', 'Bhutanese'),
  ('MV', 'Maldives', 'Maldivian'), ('AF', 'Afghanistan', 'Afghan'), ('IR', 'Iran', 'Iranian'), ('IQ', 'Iraq', 'Iraqi'), ('SA', 'Saudi Arabia', 'Saudi'), ('AE', 'United Arab Emirates|UAE', 'Emirati'),
  ('QA', 'Qatar', 'Qatari'), ('KW', 'Kuwait', 'Kuwaiti'), ('OM', 'Oman', 'Omani'), ('BH', 'Bahrain', 'Bahraini'), ('JO', 'Jordan', 'Jordanian'), ('LB', 'Lebanon', 'Lebanese'),
  ('IL', 'Israel', 'Israeli'), ('TR', 'Turkey|Türkiye', 'Turkish'), ('EG', 'Egypt', 'Egyptian'), ('KE', 'Kenya', 'Kenyan'), ('NG', 'Nigeria', 'Nigerian'), ('GH', 'Ghana', 'Ghanaian'),
  ('ZA', 'South Africa', 'South African'), ('ET', 'Ethiopia', 'Ethiopian'), ('TZ', 'Tanzania', 'Tanzanian'), ('UG', 'Uganda', 'Ugandan'), ('RW', 'Rwanda', 'Rwandan'), ('ZW', 'Zimbabwe', 'Zimbabwean'),
  ('ZM', 'Zambia', 'Zambian'), ('MW', 'Malawi', 'Malawian'), ('MZ', 'Mozambique', 'Mozambican'), ('BW', 'Botswana', 'Botswanan|Batswana'), ('MU', 'Mauritius', 'Mauritian'), ('CM', 'Cameroon', 'Cameroonian'),
  ('SN', 'Senegal', 'Senegalese'), ('MA', 'Morocco', 'Moroccan'), ('DZ', 'Algeria', 'Algerian'), ('TN', 'Tunisia', 'Tunisian'), ('BR', 'Brazil', 'Brazilian'), ('MX', 'Mexico', 'Mexican'),
  ('CO', 'Colombia', 'Colombian'), ('CL', 'Chile', 'Chilean'), ('PE', 'Peru', 'Peruvian'), ('AR', 'Argentina', 'Argentine|Argentinian'), ('EC', 'Ecuador', 'Ecuadorian'), ('VE', 'Venezuela', 'Venezuelan'),
  ('US', 'United States|USA|U.S.', 'American'), ('CA', 'Canada', 'Canadian'), ('GB', 'United Kingdom|UK|Britain|Great Britain', 'British'), ('IE', 'Ireland', 'Irish'), ('FR', 'France', 'French'), ('DE', 'Germany', 'German'),
  ('IT', 'Italy', 'Italian'), ('ES', 'Spain', 'Spanish'), ('NL', 'Netherlands', 'Dutch'), ('SE', 'Sweden', 'Swedish'), ('NO', 'Norway', 'Norwegian'), ('DK', 'Denmark', 'Danish'),
  ('FI', 'Finland', 'Finnish'), ('PL', 'Poland', 'Polish'), ('RU', 'Russia', 'Russian'), ('UA', 'Ukraine', 'Ukrainian'), ('NZ', 'New Zealand', 'New Zealander|Kiwi'), ('PG', 'Papua New Guinea|PNG', 'Papua New Guinean'),
  ('FJ', 'Fiji', 'Fijian'), ('WS', 'Samoa', 'Samoan'), ('TO', 'Tonga', 'Tongan'), ('VU', 'Vanuatu', 'ni-Vanuatu'), ('SB', 'Solomon Islands', 'Solomon Islander'), ('KI', 'Kiribati', 'I-Kiribati'),
  ('TV', 'Tuvalu', 'Tuvaluan'), ('NR', 'Nauru', 'Nauruan'), ('PW', 'Palau', 'Palauan'), ('FM', 'Micronesia', 'Micronesian'), ('MH', 'Marshall Islands', 'Marshallese'), ('CK', 'Cook Islands', 'Cook Islander'),
  ('NU', 'Niue', 'Niuean'), ('KZ', 'Kazakhstan', 'Kazakh'), ('UZ', 'Uzbekistan', 'Uzbek'), ('KG', 'Kyrgyzstan', 'Kyrgyz'), ('AZ', 'Azerbaijan', 'Azerbaijani'), ('GE', 'Georgia', 'Georgian'),
  ('AM', 'Armenia', 'Armenian'), ('R-ASEAN', 'ASEAN|South-East Asia|Southeast Asia', ''), ('R-SASIA', 'South Asia', ''), ('R-LATAM', 'Latin America|South America|Central America', ''), ('R-AFRICA', 'Africa|Sub-Saharan Africa', ''), ('R-EUROPE', 'Europe|European Union|EU', ''),
  ('R-MENA', 'Middle East|MENA|Gulf', ''), ('R-PACIFIC', 'Pacific|Pacific Islands|Oceania', ''), ('R-NASIA', 'North Asia|East Asia', ''), ('R-AMERICAS', 'the Americas|North America', ''), ('R-CARIB', 'Caribbean', ''), ('R-CASIA', 'Central Asia', '')
) v(code, names, demonyms)
on conflict (code) do nothing;
grant select on ref.nationality_terms to authenticated;

alter table scholarship.scholarships add column if not exists nationalities text[] not null default '{}';
create table if not exists scholarship.nationality_readings(
  scholarship_id uuid primary key references scholarship.scholarships(id),
  codes text[] not null, phrases jsonb not null default '{}'::jsonb, reader_version text not null, read_at timestamptz not null default now());
revoke all on scholarship.nationality_readings from public, anon, authenticated;

create or replace function security.scholarship_nationality_read_v1()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'scholarship', 'pipeline', 'security', 'ref', 'catalogue' as $f$
declare v_read int := 0; v_changed int := 0; v_with int := 0;
begin
  with t as (
    select s.id, k.iso_alpha2 study_country,
           coalesce(s.name,'') || ' ' || coalesce(s.description,'') || ' ' || coalesce((select string_agg(c.human_text, ' ') from scholarship.criteria c where c.scholarship_id = s.id), '') txt
      from scholarship.scholarships s left join catalogue.providers p on p.id = s.provider_id left join ref.countries k on k.id = p.country_id
     where s.lifecycle_status = 'active'),
  m as (
    select t.id, x.code,
           coalesce(substring(t.txt from ('(?i)\m(?:citizens?|nationals?|passport holders?|permanent residents?|residents?|students?|applicants?|candidates?|scholars?) (?:of|from) (?:the )?(?:' || x.names || ')\M')),
                    substring(t.txt from ('(?i)\m(?:' || coalesce(nullif(x.demonyms, ''), 'ZZZZ') || ') (?:citizens?|nationals?|passport holders?|students?|applicants?|candidates?)\M')),
                    substring(t.txt from ('(?i)\m(?:' || x.names || ') (?:citizens?|nationals?|passport holders?)\M'))) phrase
      from t, ref.nationality_terms x
     where x.code <> 'AU' and not (x.code = 'NZ' and t.study_country = 'AU')),
  r as (
    select t.id, coalesce((select array_agg(m.code order by m.code) from m where m.id = t.id and m.phrase is not null), '{}'::text[]) codes,
           coalesce((select jsonb_object_agg(m.code, m.phrase) from m where m.id = t.id and m.phrase is not null), '{}'::jsonb) phrases
      from t),
  up as (
    insert into scholarship.nationality_readings(scholarship_id, codes, phrases, reader_version, read_at)
    select r.id, r.codes, r.phrases, 'scholarship-nationality-v1', now() from r
    on conflict (scholarship_id) do update set codes = excluded.codes, phrases = excluded.phrases, reader_version = excluded.reader_version, read_at = now()
    returning scholarship_id, codes)
  select count(*), count(*) filter (where cardinality(codes) > 0) into v_read, v_with from up;
  update scholarship.scholarships s set nationalities = a.codes, updated_at = now() from scholarship.nationality_readings a where a.scholarship_id = s.id and s.lifecycle_status = 'active' and s.nationalities is distinct from a.codes and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id and k.field = 'nationalities');
  get diagnostics v_changed = row_count;
  if v_changed > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('scholarships', 'nationality_read', 'Nationality read from each scholarship''s wording', jsonb_build_object('read', v_read, 'with_nationality', v_with, 'changed', v_changed, 'decision', 'Decision 246'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  end if;
  return jsonb_build_object('read', v_read, 'with_nationality', v_with, 'changed', v_changed);
end $f$;
revoke all on function security.scholarship_nationality_read_v1() from public, anon, authenticated;

select cron.schedule('scholarship-nationality', '43 * * * *', $$select security.scholarship_nationality_read_v1()$$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('scholarship-nationality', 'Scholarships', 73, 'Scholarship nationality from wording',
        'Hourly: reads which nationalities each active scholarship names in its own wording (country names, demonyms and regions) and keeps the matched phrase as the basis. An empty list means the page names none. A value set by hand is never changed (Decision 246).', 5, false)
on conflict (jobname) do nothing;

select security.scholarship_nationality_read_v1();
