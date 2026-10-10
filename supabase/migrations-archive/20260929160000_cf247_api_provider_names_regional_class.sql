-- CF-247 consumer API update for the website developer's data request (29 Sep 2026), additive within the
-- website-search-v1 contract (Platform Admin approval 29 Sep 2026 11:24 IST):
--  1. provider.name is a presentable name: first CRICOS trading name (register names list several, separated by
--     ';'), HTML entities decoded, legal suffixes (Pty Ltd, Limited, Inc) removed, all-capitals names put into title
--     case with known acronyms kept. The registered name stays available as provider.legal_name. Computed at read time,
--     so register refreshes never undo it. Also used for scholarship provider names and the reference bundle's
--     provider display_name.
--  2. Campus regional classification (Department of Home Affairs, Migration (LIN 19/217: Regional Areas) Instrument
--     2019, in force from 16 Nov 2019; postcode lists as published by Home Affairs, two copies compared):
--     category 1 Major city (Sydney, Melbourne, Brisbane), 2 City or major regional centre, 3 Regional centre or other
--     regional area; metro_area names the city group. Each campus in search results carries metro_area,
--     regional_category and regional_category_name; items carry campus_metro_area; the city filter matches the campus
--     locality or its metro area ("Melbourne" now includes Clayton, Burwood and so on).
--  3. entry_requirements.summary gives the English requirement in words ("English: IELTS 6.5 (no band below 6.0),
--     PTE Academic 58"); english_requirements[] adds min_band_score. Academic entry is not held and is not implied.

create or replace function security.provider_presentable_name(p text)
returns text language sql immutable as $f$
  with a as (select replace(replace(replace(replace(replace(coalesce(p,''),'&#039;',''''),'&#39;',''''),'&amp;','&'),'&quot;','"'),'&apos;','''') x),
       b as (select btrim(split_part(x,';',1)) x from a),
       c as (select btrim(regexp_replace(regexp_replace(x,'[\s,]+(pty\.?\s*(ltd|limited)\.?|limited|ltd\.?|incorporated|inc\.?)\s*$','','i'),'[\s,]+(pty\.?\s*(ltd|limited)\.?|limited|ltd\.?)\s*$','','i')) x from b)
  select case when p is null then null
              when c.x !~ '[a-z]' and c.x ~ '[A-Z]' then
                (select string_agg(case when w ~ '^\(?(TAFE|RMIT|UNSW|ANU|UTS|QUT|ACU|CQU|JCU|NSW|QLD|VIC|TAS|WA|SA|NT|ACT|UK|USA|ELICOS|ESL|EAP|IT|IELTS|AIBT|ICHM|MIT|KOI|SIBT|UWA|ECU|CDU|USQ|USC|SCU|CIT|AIE|AIT|ATMC|NIET|IIBIT|AIH|APIC|ACBI|ACAH|CBD|RTO|VET)\)?[,.]?$' then w
                                        when ord>1 and lower(w) in ('of','and','the','for','in','at','&','de') then lower(w)
                                        else initcap(w) end, ' ' order by ord)
                   from regexp_split_to_table(c.x,'\s+') with ordinality t(w,ord))
              else c.x end
    from c
$f$;

create table if not exists ref.au_regional_postcode_ranges (
  state_code text not null, pc_from int not null, pc_to int not null, category smallint not null check (category in (2,3)),
  metro_area text, source text not null default 'Migration (LIN 19/217: Regional Areas) Instrument 2019; Home Affairs designated regional area postcodes',
  primary key (state_code, pc_from));
insert into ref.au_regional_postcode_ranges(state_code,pc_from,pc_to,category,metro_area) values
 ('AU-NSW',2259,2259,2,'Newcastle and Lake Macquarie'),('AU-NSW',2264,2308,2,'Newcastle and Lake Macquarie'),
 ('AU-NSW',2500,2526,2,'Illawarra'),('AU-NSW',2528,2535,2,'Illawarra'),('AU-NSW',2574,2574,2,'Illawarra'),
 ('AU-VIC',3211,3232,2,'Geelong'),('AU-VIC',3235,3235,2,'Geelong'),('AU-VIC',3240,3240,2,'Geelong'),('AU-VIC',3328,3328,2,'Geelong'),
 ('AU-VIC',3330,3333,2,'Geelong'),('AU-VIC',3340,3340,2,'Geelong'),('AU-VIC',3342,3342,2,'Geelong'),
 ('AU-QLD',4207,4275,2,'Gold Coast'),('AU-QLD',4517,4519,2,'Sunshine Coast'),('AU-QLD',4550,4551,2,'Sunshine Coast'),
 ('AU-QLD',4553,4562,2,'Sunshine Coast'),('AU-QLD',4564,4569,2,'Sunshine Coast'),('AU-QLD',4571,4575,2,'Sunshine Coast'),
 ('AU-WA',6000,6038,2,'Perth'),('AU-WA',6050,6083,2,'Perth'),('AU-WA',6090,6182,2,'Perth'),('AU-WA',6208,6211,2,'Perth'),
 ('AU-WA',6214,6214,2,'Perth'),('AU-WA',6556,6558,2,'Perth'),
 ('AU-SA',5000,5171,2,'Adelaide'),('AU-SA',5173,5174,2,'Adelaide'),('AU-SA',5231,5235,2,'Adelaide'),('AU-SA',5240,5252,2,'Adelaide'),
 ('AU-SA',5351,5351,2,'Adelaide'),('AU-SA',5950,5960,2,'Adelaide'),
 ('AU-TAS',7000,7000,2,'Hobart'),('AU-TAS',7004,7026,2,'Hobart'),('AU-TAS',7030,7109,2,'Hobart'),('AU-TAS',7140,7151,2,'Hobart'),('AU-TAS',7170,7177,2,'Hobart'),
 ('AU-NSW',2250,2258,3,null),('AU-NSW',2260,2263,3,null),('AU-NSW',2311,2490,3,null),('AU-NSW',2527,2527,3,null),('AU-NSW',2536,2551,3,null),
 ('AU-NSW',2575,2739,3,null),('AU-NSW',2753,2754,3,null),('AU-NSW',2756,2758,3,null),('AU-NSW',2773,2898,3,null),
 ('AU-VIC',3097,3099,3,null),('AU-VIC',3139,3139,3,null),('AU-VIC',3233,3234,3,null),('AU-VIC',3236,3239,3,null),('AU-VIC',3241,3325,3,null),
 ('AU-VIC',3329,3329,3,null),('AU-VIC',3334,3334,3,null),('AU-VIC',3341,3341,3,null),('AU-VIC',3345,3424,3,null),('AU-VIC',3430,3799,3,null),
 ('AU-VIC',3809,3909,3,null),('AU-VIC',3912,3971,3,null),('AU-VIC',3978,3996,3,null),
 ('AU-QLD',4124,4125,3,null),('AU-QLD',4133,4133,3,null),('AU-QLD',4183,4184,3,null),('AU-QLD',4280,4287,3,null),('AU-QLD',4306,4498,3,null),
 ('AU-QLD',4507,4507,3,null),('AU-QLD',4552,4552,3,null),('AU-QLD',4563,4563,3,null),('AU-QLD',4570,4570,3,null),('AU-QLD',4580,4895,3,null)
on conflict do nothing;

create or replace function security.au_regional_class(p_state text, p_postcode text)
returns jsonb language sql stable as $f$
  with x as (select upper(btrim(p_state)) st, case when btrim(coalesce(p_postcode,'')) ~ '^\d{4}$' then btrim(p_postcode)::int end pc),
  r as (select g.category, g.metro_area from ref.au_regional_postcode_ranges g, x where g.state_code=x.st and x.pc between g.pc_from and g.pc_to order by g.category limit 1)
  select case
    when x.st is null or x.st !~ '^AU-' or x.pc is null then null
    when x.st='AU-ACT' then jsonb_build_object('category',2,'metro_area','Canberra')
    when x.st='AU-NT' or x.pc=2899 then jsonb_build_object('category',3,'metro_area',null)
    when exists (select 1 from r) then (select jsonb_build_object('category',r.category,'metro_area',r.metro_area) from r)
    when x.st in ('AU-WA','AU-SA','AU-TAS') then jsonb_build_object('category',3,'metro_area',null)
    when x.st='AU-NSW' then jsonb_build_object('category',1,'metro_area','Sydney')
    when x.st='AU-VIC' then jsonb_build_object('category',1,'metro_area','Melbourne')
    when x.st='AU-QLD' then jsonb_build_object('category',1,'metro_area','Brisbane')
  end from x
$f$;

create table if not exists pipeline.campus_regional_class (
  campus_id uuid primary key, state_code text, postcode text, category smallint, category_name text, metro_area text, computed_at timestamptz not null default now());
alter table pipeline.campus_regional_class enable row level security;
create or replace function security.campus_regional_class_refresh_v1()
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','catalogue','pipeline','ref','security' as $f$
declare n int;
begin
  insert into pipeline.campus_regional_class(campus_id,state_code,postcode,category,category_name,metro_area,computed_at)
  select k.id, s.code, k.postcode, (c->>'category')::smallint,
         case (c->>'category')::int when 1 then 'Major city' when 2 then 'City or major regional centre' when 3 then 'Regional centre or other regional area' end,
         c->>'metro_area', now()
    from catalogue.campuses k left join ref.subdivisions s on s.id=k.subdivision_id
    cross join lateral (select security.au_regional_class(s.code,k.postcode) c) z
  on conflict (campus_id) do update set state_code=excluded.state_code, postcode=excluded.postcode, category=excluded.category,
         category_name=excluded.category_name, metro_area=excluded.metro_area, computed_at=now()
   where pipeline.campus_regional_class.postcode is distinct from excluded.postcode or pipeline.campus_regional_class.state_code is distinct from excluded.state_code
      or pipeline.campus_regional_class.category is distinct from excluded.category;
  get diagnostics n=row_count;
  return jsonb_build_object('changed',n);
end $f$;
revoke all on function security.campus_regional_class_refresh_v1() from public, anon, authenticated;
select security.campus_regional_class_refresh_v1();
select cron.schedule('campus-regional-class-refresh','41 3 * * *',$$select security.campus_regional_class_refresh_v1()$$);
