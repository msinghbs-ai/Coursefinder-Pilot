-- CF-247 (4 Oct 2026, 00:30 AEST). Platform Admin, 00:09: "there is no scholarships for NZ and Canada, if they [have]
-- sources, register them in layer1 and ingest data, cross link with courses internally". Decision 250.
-- Found: scholarship discovery only ever queued Australian providers; admission accepted Australian universities only;
-- every amount was stored and labelled as AUD; the domestic-wording rules named only Australian terms.
-- Canada's providers have no website on the provider record; the verified sites are in the website finder
-- (pipeline.coverage_provider_discovery), which scholarship discovery now uses.
--   1. Helpers: scholarship.provider_currency (the provider country's currency), scholarship.money_prefix (A$, NZ$, C$),
--      security.scholarship_university (Australian rule unchanged; New Zealand and Canadian universities added).
--   2. Admission, the page apply, the criteria apply, the page tiers, the value label and the hand edit use the
--      provider country's currency, never a fixed AUD. Stable keys carry the provider's country.
--   3. Who it is for (Decision 244) and nationalities (Decision 246) read domestic wording for the study country.
--   4. Discovery: New Zealand and Canadian universities with a verified website are queued now (priority 1); the hourly
--      refill covers every country with scholarship ingestion on.
--   5. Layer 1: Manaaki New Zealand Scholarships (MFAT) and Study in Canada Scholarships (Global Affairs Canada)
--      registered as government programme sources. Manaaki scholarships are published on each New Zealand university's
--      own page, so they are read and linked to courses through that page; Study in Canada Scholarships are short
--      exchanges for students enrolled abroad, not degree study, so they are registered but not linked to courses.
--   6. The workers get the provider's currency with each page to read.
--   7. The scholarship record lists the courses it is linked to (up to 200, by study level).
-- Each replaced function is md5-guarded on its live text and every patched snippet must be found exactly once.

create or replace function scholarship.provider_currency(p_provider_id uuid) returns text
language sql stable security definer set search_path = '' as $f$
  select coalesce((select k.default_currency_code from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = p_provider_id), 'AUD')
$f$;
create or replace function scholarship.money_prefix(p_currency text) returns text
language sql immutable set search_path = '' as $f$
  select case upper(coalesce(p_currency, 'AUD')) when 'AUD' then 'A$' when 'NZD' then 'NZ$' when 'CAD' then 'C$' when 'USD' then 'US$' when 'GBP' then '£' else upper(p_currency) || ' ' end
$f$;
create or replace function security.scholarship_university(p_provider_id uuid) returns boolean
language sql stable security definer set search_path = '' as $f$
  select security.australian_university(p_provider_id)
      or exists (select 1 from catalogue.providers p join ref.countries c on c.id = p.country_id
                  where p.id = p_provider_id and c.iso_alpha2 in ('NZ', 'CA') and c.scholarship_ingestion_enabled and p.lifecycle_status = 'active'
                    and (jsonb_array_length(coalesce(security.provider_university_groups(p.id), '[]')) > 0
                         or (p.canonical_name ~* '\m(university|université|universite)\M' and p.canonical_name !~* '(college|pathways?|language cent|senior|theology|divinity)')))
$f$;
create or replace function security.scholarship_tier_text(p_pcts numeric[], p_amts numeric[], p_up_to boolean, p_currency text) returns text
language sql immutable set search_path = '' as $f$
  select array_to_string(array_remove(array[
    case when cardinality(coalesce(p_pcts, '{}'::numeric[])) = 1 then p_pcts[1]::int || '% of tuition fees'
         when cardinality(coalesce(p_pcts, '{}'::numeric[])) > 1 then case when p_up_to then 'Up to ' || p_pcts[cardinality(p_pcts)]::int || '% of tuition fees (' || (select string_agg(x::int || '%', ', ') from unnest(p_pcts) x) || ' stated)'
                                                                       else p_pcts[1]::int || '% to ' || p_pcts[cardinality(p_pcts)]::int || '% of tuition fees' end end,
    case when cardinality(coalesce(p_amts, '{}'::numeric[])) = 1 then scholarship.money_prefix(p_currency) || to_char(p_amts[1], 'FM999,999,999')
         when cardinality(coalesce(p_amts, '{}'::numeric[])) > 1 then case when p_up_to then 'Up to ' || scholarship.money_prefix(p_currency) || to_char(p_amts[cardinality(p_amts)], 'FM999,999,999') || ' (' || (select string_agg(scholarship.money_prefix(p_currency) || to_char(x, 'FM999,999,999'), ', ') from unnest(p_amts) x) || ' stated)'
                                                                       else scholarship.money_prefix(p_currency) || to_char(p_amts[1], 'FM999,999,999') || ' to ' || scholarship.money_prefix(p_currency) || to_char(p_amts[cardinality(p_amts)], 'FM999,999,999') end end
  ], null), ' or ')
$f$;
revoke all on function scholarship.provider_currency(uuid) from public, anon;
revoke all on function security.scholarship_university(uuid) from public, anon, authenticated;
grant execute on function scholarship.provider_currency(uuid) to authenticated;
grant execute on function scholarship.money_prefix(text) to authenticated;

do $g$
declare v_oid oid; v_def text; p record; v_fn text := ''; v_n int;
begin
  for p in select * from (values
    -- value label
    (1, 'scholarship', 'value_label', '46aa11dbfd0a5b744190aa1c5e65a96e',
      $x$case when coalesce(s.award_currency_code, 'AUD') = 'AUD' then 'A$' else s.award_currency_code || ' ' end$x$,
      $x$scholarship.money_prefix(coalesce(s.award_currency_code, 'AUD'))$x$),
    -- admission: universities in a scholarship country; the stable key carries the provider's country
    (2, 'security', 'scholarship_admit_from_provider_page_v1', '13f32cea3c7981dc2f3f9cf8eec280b4',
      $x$elsif not security.australian_university(c.provider_id) then r:=jsonb_build_object('admitted',false,'reason','not an Australian university provider');$x$,
      $x$elsif not security.scholarship_university(c.provider_id) then r:=jsonb_build_object('admitted',false,'reason','not a university provider in a scholarship country');$x$),
    (3, 'security', 'scholarship_admit_from_provider_page_v1', null,
      $x$v_key:='scholarship:AU:first-party:'||$x$,
      $x$v_key:='scholarship:'||coalesce((select k.iso_alpha2 from catalogue.providers pp join ref.countries k on k.id=pp.country_id where pp.id=c.provider_id),'AU')||':first-party:'||$x$),
    -- page apply
    (4, 'security', 'scholarship_sweep_apply_v1', '85cdf490d2831976e95b0c27443fd771',
      $x$award_amount=(f->'value'->>'amount')::numeric, award_currency_code='AUD',$x$,
      $x$award_amount=(f->'value'->>'amount')::numeric, award_currency_code=scholarship.provider_currency(s.provider_id),$x$),
    -- criteria apply (a maximum amount)
    (5, 'security', 'scholarship_criteria_apply_v1', '2d07a2a4eedda7a14262a0a58692332f',
      $x$award_amount = amt, award_currency_code = 'AUD', award_value_is_maximum = true,$x$,
      $x$award_amount = amt, award_currency_code = scholarship.provider_currency(s.provider_id), award_value_is_maximum = true,$x$),
    (6, 'security', 'scholarship_criteria_apply_v1', null,
      $x$award_value_text = coalesce(award_value_text, 'Up to A$' || to_char(amt, 'FM999,999,999')),$x$,
      $x$award_value_text = coalesce(award_value_text, 'Up to ' || scholarship.money_prefix(scholarship.provider_currency(s.provider_id)) || to_char(amt, 'FM999,999,999')),$x$),
    -- page tiers (Decision 245)
    (7, 'security', 'scholarship_award_tiers_from_page_v1', 'a045f3415ebbd3e679d2e681ff3a2e41',
      $x$award_value_text = security.scholarship_tier_text(c.pcts, c.amts, c.up_to) from$x$,
      $x$award_value_text = security.scholarship_tier_text(c.pcts, c.amts, c.up_to, scholarship.provider_currency(s.provider_id)) from$x$),
    (8, 'security', 'scholarship_award_tiers_from_page_v1', null,
      $x$'Stated on the page', null, a, 'AUD', 'as_stated',$x$,
      $x$'Stated on the page', null, a, scholarship.provider_currency((select x.provider_id from scholarship.scholarships x where x.id = c.id)), 'as_stated',$x$),
    -- who it is for: domestic wording for the study country
    (9, 'security', 'scholarship_audience_read_v1', 'bd0ca8421d0990e26e0a1ccab023f1ef',
      $x$  c_both constant text :=$x$,
      $x$  c_dom_nz constant text := '\m(domestic students?|new zealand citizens?|new zealand permanent residents?|permanent residen(t|cy) of new zealand|australian citizens?|home students?|fees[- ]free|studylink|student allowance|maori|māori|pasifika)\M';
  c_dom_ca constant text := '\m(domestic students?|canadian citizens?|canadian permanent residents?|permanent residents? of canada|protected persons?|indigenous|first nations|métis|metis|inuit|osap|canada student (loans?|grants?)|residents? of (british columbia|alberta|ontario|quebec|québec|manitoba|saskatchewan|nova scotia|new brunswick))\M';
  c_both constant text :=$x$),
    (10, 'security', 'scholarship_audience_read_v1', null,
      $x$    select s.id, lower(coalesce(s.name,'') || ' ' || coalesce(s.description,'') || ' ' || coalesce((select string_agg(c.human_text, ' ') from scholarship.criteria c where c.scholarship_id = s.id), '')) txt
      from scholarship.scholarships s where s.lifecycle_status = 'active'),$x$,
      $x$    select s.id, lower(coalesce(s.name,'') || ' ' || coalesce(s.description,'') || ' ' || coalesce((select string_agg(c.human_text, ' ') from scholarship.criteria c where c.scholarship_id = s.id), '')) txt,
           (select k.iso_alpha2 from catalogue.providers pp join ref.countries k on k.id = pp.country_id where pp.id = s.provider_id) cc
      from scholarship.scholarships s where s.lifecycle_status = 'active'),$x$),
    (11, 'security', 'scholarship_audience_read_v1', null,
      $x$substring(t.txt from c_dom) p_dom$x$,
      $x$substring(t.txt from case t.cc when 'NZ' then c_dom_nz when 'CA' then c_dom_ca else c_dom end) p_dom$x$),
    -- nationalities: the study country's own citizens are not a nationality restriction
    (12, 'security', 'scholarship_nationality_read_v1', '55b7c74da01b3d54620f0e0df46475a4',
      $x$     where x.code <> 'AU' and not (x.code = 'NZ' and t.study_country = 'AU')),$x$,
      $x$     where x.code <> coalesce(t.study_country, 'AU') and not (x.code = 'AU' and coalesce(t.study_country, 'AU') in ('AU', 'NZ')) and not (x.code = 'NZ' and t.study_country = 'AU')),$x$),
    -- publishing check: Canadian citizens wording
    (13, 'security', 'scholarship_publishability_v1', '265908a52a6e05ac591df3c1bae446b7',
      $x$'(australian citizen|permanent resident|domestic student|new zealand citizen)'$x$,
      $x$'(australian citizen|permanent resident|domestic student|new zealand citizen|canadian citizen)'$x$),
    -- hand edit: the provider's currency
    (14, 'public', 'admin_scholarship_edit', '13163280d09fd599c6e86406a92d42f0',
      $x$coalesce(award_currency_code, 'AUD')$x$,
      $x$coalesce(award_currency_code, scholarship.provider_currency(provider_id))$x$),
    -- workers: the provider's currency with each page
    (15, 'public', 'svc_scholarship_candidate_next', '905110339fc8ad0f640f7a4e67b118b8',
      $x$jsonb_build_object('candidate_id',u.id,'url',u.url,'provider_id',u.provider_id,$x$,
      $x$jsonb_build_object('candidate_id',u.id,'url',u.url,'provider_id',u.provider_id,'currency',scholarship.provider_currency(u.provider_id),$x$),
    (16, 'public', 'svc_scholarship_read_next', 'b66765c8669338b7d921adaa2c8674e5',
      $x$'provider_id',s.provider_id,'url_source',u.url_source,$x$,
      $x$'provider_id',s.provider_id,'currency',scholarship.provider_currency(s.provider_id),'url_source',u.url_source,$x$),
    -- the record lists its courses
    (17, 'public', 'admin_scholarship_record_read', '21f3cbaeef1962d6cece62c647bed72c',
      $x$      'courses', (select count(*) from scholarship.course_mappings m where m.scholarship_id = s.id and m.mapping_state = 'mapped'),$x$,
      $x$      'courses', (select count(*) from scholarship.course_mappings m where m.scholarship_id = s.id and m.mapping_state = 'mapped'),
      'course_list', (select coalesce(jsonb_agg(jsonb_build_object('id', x.id, 'title', x.title, 'level', x.level, 'code', x.course_code) order by x.so, x.title), '[]'::jsonb)
                        from (select co.id, coalesce(co.display_title, co.canonical_title) title, sl.name level, coalesce(sl.sort_order, 99) so, co.course_code
                                from scholarship.course_mappings m join catalogue.courses co on co.id = m.course_id left join ref.study_levels sl on sl.id = co.study_level_id
                               where m.scholarship_id = s.id and m.mapping_state = 'mapped' and co.lifecycle_status = 'active'
                               order by coalesce(sl.sort_order, 99), coalesce(co.display_title, co.canonical_title) limit 200) x),
      'course_levels', (select coalesce(jsonb_agg(jsonb_build_object('level', y.level, 'courses', y.n) order by y.so), '[]'::jsonb)
                          from (select coalesce(sl.name, 'Other') level, min(coalesce(sl.sort_order, 99)) so, count(*) n
                                  from scholarship.course_mappings m join catalogue.courses co on co.id = m.course_id left join ref.study_levels sl on sl.id = co.study_level_id
                                 where m.scholarship_id = s.id and m.mapping_state = 'mapped' and co.lifecycle_status = 'active' group by 1) y),$x$)
  ) t(ord, sch, fn, md, old_s, new_s) order by ord loop
    if p.sch || '.' || p.fn <> v_fn then
      if v_fn <> '' then execute v_def; end if;
      select pr.oid into v_oid from pg_proc pr join pg_namespace n on n.oid = pr.pronamespace where n.nspname = p.sch and pr.proname = p.fn;
      if (select md5(prosrc) from pg_proc where oid = v_oid) is distinct from p.md then raise exception '%.% changed; not replacing', p.sch, p.fn; end if;
      v_def := pg_get_functiondef(v_oid); v_fn := p.sch || '.' || p.fn;
    end if;
    v_n := (length(v_def) - length(replace(v_def, p.old_s, ''))) / length(p.old_s);
    if v_n <> 1 then raise exception 'patch % (%): found % times', p.ord, v_fn, v_n; end if;
    v_def := replace(v_def, p.old_s, p.new_s);
  end loop;
  execute v_def;
end $g$;

-- 4. Discovery: every country with scholarship ingestion on; outside Australia, universities only (only they are
--    admitted), with the website on the provider record or the one the website finder verified.
do $g$ begin
  if (select md5(prosrc) from pg_proc where oid = 'security.scholarship_discovery_refill_v1(int)'::regprocedure) is distinct from 'ec5055b2666cad165bde5f58bf9c7fd9' then raise exception 'scholarship_discovery_refill_v1 changed; not replacing'; end if;
end $g$;
create or replace function security.scholarship_discovery_refill_v1(p_keep int default 30) returns jsonb
language plpgsql security definer set search_path = '' as $fn$
declare v_pending int; v_added int := 0;
begin
  select count(*) into v_pending from pipeline.scholarship_discovery_providers where status = 'pending';
  if v_pending < p_keep then
    insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status)
    select q.provider_id, q.website, case when q.cc = 'AU' then 4 else 1 end, case when q.cc = 'AU' then 'largest_unsearched' else 'university_' || lower(q.cc) end, 'pending'
      from (select p.id provider_id, k.iso_alpha2 cc,
                   coalesce(nullif(btrim(p.website), ''), (select nullif(btrim(d.website), '') from pipeline.coverage_provider_discovery d where d.provider_id = p.id and d.status = 'mapped')) website,
                   count(*) n
              from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
             where co.lifecycle_status = 'active' and k.scholarship_ingestion_enabled
               and (k.iso_alpha2 = 'AU' or security.scholarship_university(p.id))
               and not exists (select 1 from pipeline.scholarship_discovery_providers d where d.provider_id = p.id)
             group by p.id, p.website, k.iso_alpha2) q
     where q.website is not null
     order by (q.cc <> 'AU') desc, q.n desc, q.provider_id limit greatest(0, p_keep - v_pending)
    on conflict do nothing;
    get diagnostics v_added = row_count;
  end if;
  return jsonb_build_object('pending_before', v_pending, 'added', v_added);
end $fn$;
revoke all on function security.scholarship_discovery_refill_v1(int) from public, anon, authenticated;

-- queue the New Zealand and Canadian universities now
insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status)
select p.id, coalesce(nullif(btrim(p.website), ''), d.website), 1, 'university_' || lower(k.iso_alpha2), 'pending'
  from catalogue.providers p join ref.countries k on k.id = p.country_id
  left join pipeline.coverage_provider_discovery d on d.provider_id = p.id and d.status = 'mapped'
 where k.iso_alpha2 in ('NZ', 'CA') and security.scholarship_university(p.id)
   and coalesce(nullif(btrim(p.website), ''), nullif(btrim(d.website), '')) is not null
   and exists (select 1 from catalogue.courses co where co.provider_id = p.id and co.lifecycle_status = 'active')
on conflict do nothing;

-- 5. Layer 1: government programme sources
insert into pipeline.sources(source_type, provider_id, country_id, url, label, trust_rank, status, metadata)
select 'government_scholarship_program', null, k.id, v.url, v.label, 100, 'active', v.meta
  from (values
    ('NZ', 'https://www.nzscholarships.govt.nz/', 'Manaaki New Zealand Scholarships',
     jsonb_build_object('layer', '1', 'domain', 'scholarship', 'publisher', 'Ministry of Foreign Affairs and Trade (New Zealand)', 'authority_class', 'official_government_program',
                        'identity_authority', false, 'scholarship_source_key', 'nz_mfat_manaaki', 'decision', 'Decision 250',
                        'ingestion', 'Each New Zealand university publishes its Manaaki page; scholarships are read from those pages and linked to the university''s courses.')),
    ('CA', 'https://www.educanada.ca/scholarships-bourses/can/institutions/study-in-canada-sep-etudes-au-canada-pct.aspx?lang=eng', 'Study in Canada Scholarships (Global Affairs Canada)',
     jsonb_build_object('layer', '1', 'domain', 'scholarship', 'publisher', 'Global Affairs Canada (EduCanada)', 'authority_class', 'official_government_program',
                        'identity_authority', false, 'scholarship_source_key', 'ca_gac_study_in_canada', 'decision', 'Decision 250',
                        'ingestion', 'Short-term exchange scholarships for students enrolled outside Canada; registered for reference, not linked to degree courses.'))
  ) v(cc, url, label, meta) join ref.countries k on k.iso_alpha2 = v.cc
 where not exists (select 1 from pipeline.sources s where s.url = v.url);
