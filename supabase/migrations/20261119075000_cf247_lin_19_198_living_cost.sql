-- CF-247 s719: Home Affairs financial-capacity living cost from LIN 19/198, corroborated by the Home Affairs Step by step tab (S2-Build;
-- Platform Admin 19 Nov 2026 06:41: "Register Migration (LIN 19/198 ...) Instrument 2019 (legislation.gov.au, CC BY 4.0) under Layer 1 Register ›
-- Australia (with a Firecrawl Step by step tab capture on immi.homeaffairs.gov.au as corroborating evidence), route through standard Layer 1
-- Storage + Evidence records, and publish the verified annual primary-applicant living-cost benchmark (AUD 29,710) into the live Home Affairs
-- study rules edition"; 06:45: every source is registered in the Layer 1 Register first, by country).
--
-- What was read (19 Nov 2026 07:00 AEDT): the Home Affairs living-cost fact has never been found: the rendered student visa page's main content
-- holds no amount (the anchor windows are the fee-concession text). The instrument's current compilation (No. 2, 10 May 2024, F2024L00529
-- included) is a static page on the Federal Register of Legislation stating "(A) if the primary applicant intends to stay in Australia for a
-- period of 12 months or more—AUD29,710 (primary applicant annual living costs)". The published Home Affairs edition is
-- "... pages (read 19 Nov 2026)", with 5 rules and no visa_funds rule.
--
-- What it changes (data in existing tables and four md5-guarded edits of one existing function; no new table or function; G3 75/48):
--   1. Layer 1 Register › Australia: "LIN 19/198 Evidence of Financial Capacity (Subclass 500 and 590)": regulatory, Federal Register of
--      Legislation, authority domains legislation.gov.au and www.legislation.gov.au, HTML, rules, check and load every 30 days, licence CC BY 4.0,
--      attribution in its metadata. Due in the follow-up change, once loader v1.5.0 is deployed.
--   2. destination.page_facts: the instrument's fact (read directly, no Firecrawl) for the existing rule "Student visa (subclass 500) 12-month
--      living cost (financial capacity)" (visa_funds, AUD a year, 20,000 to 40,000); the Home Affairs fact for the same rule now reads the Step by
--      step tab (page address ending #HowTo, read whole by loader v1.5.0) and also matches "you" before the amount (the range keeps the partner and
--      child amounts out).
--   3. security.destination_page_facts_load_v1:
--      a. a successor edition's label carries one read date, and a time when a second successor opens on the same day (was: "(read 19 Nov 2026)"
--         appended again, which would have named the published edition itself);
--      b. a successor edition's attribution adds the attribution of every other registered destination source a fact of this run came from
--         (here LIN 19/198, CC BY 4.0) to the edition's own;
--      c. a rule updated from a second page names that page (source_url), so quote, evidence and page always agree;
--      d. two official sources for one rule that give different values are both held ("a person decides"); neither writes the rule;
--      e. every rule of the edition written gets one proven country applicability (a national authority's rule applies to every course of its
--         country), citing the rule's page and quote: until now no rule had one, so Around this course showed no visa or living-cost rule.
--   4. The five rules of the published Home Affairs edition get the same country applicability (backfill).
-- Nothing is dropped or deleted.
-- Replaces: the main-content read of the Home Affairs living-cost fact (now the Step by step tab, read whole).
-- Retires: nothing.

-- 1. the source, in the Layer 1 Register (existing registry), under Australia
with au as (select id from ref.countries where iso_alpha2 = 'AU')
insert into pipeline.sources(source_type, country_id, url, label, trust_rank, status, metadata)
select 'web', (select id from au),
       'https://www.legislation.gov.au/F2019L01366/2024-05-10/2024-05-10/text/original/epub/OEBPS/document_1/document_1.html',
       'LIN 19/198 Evidence of Financial Capacity (Subclass 500 and 590)', 1, 'active',
       jsonb_build_object('layer', 'layer1', 'source_system', 'DESTINATION', 'dataset_class', 'regulatory', 'destination_mode', 'facts',
         'destination_scope', 'pages', 'parser', 'Regulatory / page-facts reader (static compilation page; verbatim quotes)',
         'publisher', 'Federal Register of Legislation (Office of Parliamentary Counsel); made by the Department of Home Affairs',
         'licence', 'CC BY 4.0',
         'attribution', 'Living-cost amount: Migration (LIN 19/198: Evidence of financial capacity—Subclass 500 Visa and Subclass 590 Visa) Instrument 2019 (F2019L01366, compilation No. 2), Federal Register of Legislation, legislation.gov.au. © Commonwealth of Australia, licensed under Creative Commons Attribution 4.0 International (CC BY 4.0).',
         'instrument', 'F2019L01366', 'compilation', 'No. 2, 10 May 2024 (includes F2024L00529)',
         'destination_edition', 'Home Affairs Student visa (subclass 500) and Temporary Graduate visa (subclass 485) pages',
         'operational_surface', 'Destination data', 'schedule_day_sydney', 3,
         'decision', 'Platform Admin 19 Nov 2026 06:41 (S2-Build, s719): LIN 19/198 in the Layer 1 Register, Home Affairs Step by step tab corroborates')
 where not exists (select 1 from pipeline.sources s where s.label = 'LIN 19/198 Evidence of Financial Capacity (Subclass 500 and 590)'
                     and s.metadata->>'source_system' = 'DESTINATION');

insert into pipeline.layer1_source_operations(source_id, authority_name, authority_domains, expected_format, expected_count_kind, active, paused,
       verification_cadence_days, ingestion_cadence_days, variance_warn_percent, variance_block_percent, auto_ingest, next_verification_at, change_reason)
select s.id, s.metadata->>'publisher', array['legislation.gov.au', 'www.legislation.gov.au'], 'Federal Register of Legislation compilation page (static HTML)',
       'rules', true, false, 30, 30, 20, 60, true, null,  -- monthly; variance warn 20%, block 60%; made due by the follow-up change
       'Registered 19 Nov 2026 (20261119075000, s719): living-cost amount for the Home Affairs study rules edition'
  from pipeline.sources s
 where s.label = 'LIN 19/198 Evidence of Financial Capacity (Subclass 500 and 590)' and s.metadata->>'source_system' = 'DESTINATION'
   and not exists (select 1 from pipeline.layer1_source_operations o where o.source_id = s.id);

-- 2. the facts
insert into destination.page_facts(country_code, edition_label, page_url, kind, rule_category, title, applicant_scope, pattern, flags, unit,
       currency_code, min_value, max_value, anchor, status, read_mode, note)
select 'AU', f.edition_label,
       'https://www.legislation.gov.au/F2019L01366/2024-05-10/2024-05-10/text/original/epub/OEBPS/document_1/document_1.html',
       'amount', f.rule_category, f.title, f.applicant_scope,
       'AUD\s?([0-9]{2},[0-9]{3})\s*\(primary applicant annual living costs\)', 'i', f.unit, 'AUD', 20000, 40000,
       'primary applicant annual living costs', 'active', 'static',
       'Seeded 19 Nov 2026 (20261119075000, s719): LIN 19/198 subsection 6(2), compilation No. 2; the Home Affairs Step by step tab corroborates'
  from destination.page_facts f
 where f.id = '5c795851-f84c-4453-8675-12059376e039'
   and not exists (select 1 from destination.page_facts g where g.page_url like 'https://www.legislation.gov.au/F2019L01366/%' and g.title = f.title);

update destination.page_facts
   set page_url = 'https://immi.homeaffairs.gov.au/visas/getting-a-visa/visa-listing/student-500#HowTo',
       pattern = '(?:primary applicant|student or guardian|student/guardian|student primary applicant|\byou\b)[^0-9]{0,160}?AUD\s?\$?\s?([0-9]{2},[0-9]{3})',
       anchor = 'living cost|financial capacity|12 months',
       min_value = 20000, max_value = 40000,
       note = note || '; 19 Nov 2026 (20261119075000, s719): reads the Step by step tab (#HowTo, read whole); corroborates LIN 19/198',
       updated_at = now()
 where id = '5c795851-f84c-4453-8675-12059376e039' and page_url not like '%#HowTo';

-- 3. the load function
create or replace function pg_temp.cf_edit_many(p_sig regprocedure, p_md5 text, p_old text[], p_new text[], p_marker text)
returns void language plpgsql as $f$
declare v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig); v_def text; v_body text; v_c int; i int;
begin
  if position(p_marker in v_src) > 0 then raise notice '%: already applied', p_sig; return; end if;
  if md5(v_src) <> p_md5 then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(pg_get_functiondef(p_sig), chr(13), ''); v_body := v_src;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]); v_body := replace(v_body, p_old[i], p_new[i]);
  end loop;
  execute v_def;
  if md5((select p.prosrc from pg_proc p where p.oid = p_sig)) <> md5(v_body) then raise exception '% after the edits is not the expected body', p_sig; end if;
end $f$;

select pg_temp.cf_edit_many('security.destination_page_facts_load_v1(jsonb)'::regprocedure, '47cf7bd563d3c1638d727fd419d1f30c',
  array[
    $o1$        v_label := e.edition_label || ' (read ' || v_day || ')';$o1$,
    $o2$          values (e.country_id, e.domain, v_label, current_date, 'draft', e.source_url, e.source_owner, e.attribution_text, e.terms_status, now())$o2$,
    $o3$          update destination.study_rules set numeric_threshold = v_val, quote_on_page = fd->>'quote', evidence_id = coalesce(nullif(fd->>'evidence_id', '')::uuid, evidence_id),$o3$,
    $o4$        select * into f from destination.page_facts where id = (fd->>'fact_id')::uuid;
        v_val := nullif(fd->>'value', '')::numeric; v_read := (fd->>'read_at')::timestamptz;$o4$,
    $o5$          v_unchanged := v_unchanged + 1;
        end if;
      end loop;
    end loop;
  end if;

  -- the JSA OSCA occupation workbook$o5$
  ],
  array[
    $n1$        -- 20261119075000 (s719): one read date in a successor's label, and a time when a second successor opens on the same day
        v_label := regexp_replace(e.edition_label, '\s\(read [^)]*\)$', '') || ' (read ' || v_day || ')';
        if v_label = e.edition_label then
          v_label := regexp_replace(e.edition_label, '\s\(read [^)]*\)$', '') || ' (read ' || v_day || ', ' || to_char(now() at time zone 'Australia/Sydney', 'HH24:MI') || ')';
        end if;$n1$,
    $n2$          values (e.country_id, e.domain, v_label, current_date, 'draft', e.source_url, e.source_owner,
                  -- 20261119075000 (s719): the attribution of every other registered destination source a fact of this run came from
                  e.attribution_text || coalesce((select ' ' || string_agg(distinct src.metadata->>'attribution', ' ')
                     from jsonb_array_elements(v_found) z
                     join pipeline.layer1_source_operations o on lower(substring(z->>'page_url' from '^https?://([^/:?#]+)')) = any (o.authority_domains)
                     join pipeline.sources src on src.id = o.source_id
                    where (z->>'edition_id')::uuid = e.id and src.metadata->>'source_system' = 'DESTINATION'
                      and coalesce(src.metadata->>'attribution', '') <> '' and position(src.metadata->>'attribution' in coalesce(e.attribution_text, '')) = 0), ''),
                  e.terms_status, now())$n2$,
    $n3$          update destination.study_rules set numeric_threshold = v_val, quote_on_page = fd->>'quote', evidence_id = coalesce(nullif(fd->>'evidence_id', '')::uuid, evidence_id),
                 source_url = fd->>'page_url',  -- 20261119075000 (s719): the rule names the page its quote is from$n3$,
    $n4$        select * into f from destination.page_facts where id = (fd->>'fact_id')::uuid;
        v_val := nullif(fd->>'value', '')::numeric; v_read := (fd->>'read_at')::timestamptz;
        -- 20261119075000 (s719): two official sources for one rule must agree; when they do not, both are held and a person decides
        if exists (select 1 from jsonb_array_elements(v_found) z2 join destination.page_facts p2 on p2.id = (z2->>'fact_id')::uuid
                    where (z2->>'edition_id')::uuid = v_ed and p2.id <> f.id and p2.rule_category = f.rule_category and p2.title = f.title
                      and nullif(z2->>'value', '')::numeric is distinct from v_val) then
          update destination.page_facts set last_status = 'held', last_reason = 'Two official sources for this rule give different values; a person decides', updated_at = now()
           where id = f.id;
          v_differs := v_differs + 1;
          continue;
        end if;$n4$,
    $n5$          v_unchanged := v_unchanged + 1;
        end if;
      end loop;
      -- 20261119075000 (s719): a national authority's rule applies to every course of its country: one proven country applicability per rule
      insert into destination.rule_applicability(rule_id, entity_type, entity_id, entity_code, applicability_status, evidence_url, quote_on_page, verified_at)
      select r.id, 'country', r.country_id, (select c.iso_alpha2 from ref.countries c where c.id = r.country_id), 'proven', r.source_url, r.quote_on_page,
             coalesce(r.last_checked_at, now())
        from destination.study_rules r
       where r.edition_id = e.id and r.country_id is not null and r.approval_status in ('draft', 'approved')
         and not exists (select 1 from destination.rule_applicability a where a.rule_id = r.id and a.entity_type = 'country');
    end loop;
  end if;

  -- the JSA OSCA occupation workbook$n5$
  ],
  '20261119075000 (s719)');

-- 4. country applicability for the rules of the published Home Affairs edition (backfill; the load writes it from now on)
insert into destination.rule_applicability(rule_id, entity_type, entity_id, entity_code, applicability_status, evidence_url, quote_on_page, verified_at)
select r.id, 'country', r.country_id, c.iso_alpha2, 'proven', r.source_url, r.quote_on_page, coalesce(r.last_checked_at, now())
  from destination.study_rules r join destination.editions e on e.id = r.edition_id join ref.countries c on c.id = r.country_id
 where e.domain = 'study_rules' and e.status = 'published' and r.approval_status = 'approved'
   and not exists (select 1 from destination.rule_applicability a where a.rule_id = r.id and a.entity_type = 'country');

-- post-checks (rolled back with the dry run if any fails)
do $chk$
declare v_drift jsonb; v_n int;
begin
  select count(*) into v_n from pipeline.sources s join pipeline.layer1_source_operations o on o.source_id = s.id
   where s.label = 'LIN 19/198 Evidence of Financial Capacity (Subclass 500 and 590)' and 'www.legislation.gov.au' = any (o.authority_domains) and o.active and not o.paused;
  if v_n <> 1 then raise exception 'post-check: LIN 19/198 is not registered once in the Layer 1 Register (%)', v_n; end if;
  select count(*) into v_n from destination.page_facts where title = 'Student visa (subclass 500) 12-month living cost (financial capacity)' and status = 'active'
     and (page_url like 'https://www.legislation.gov.au/F2019L01366/%' or page_url like '%student-500#HowTo');
  if v_n <> 2 then raise exception 'post-check: expected the instrument fact and the Step by step fact (%)', v_n; end if;
  if (select count(*) from pg_proc where prosrc like '%20261119075000 (s719)%' and oid = 'security.destination_page_facts_load_v1(jsonb)'::regprocedure) <> 1 then
    raise exception 'post-check: the load function was not edited';
  end if;
  if exists (select 1 from destination.study_rules r join destination.editions e on e.id = r.edition_id
              where e.domain = 'study_rules' and e.status = 'published' and r.approval_status = 'approved'
                and not exists (select 1 from destination.rule_applicability a where a.rule_id = r.id and a.entity_type = 'country')) then
    raise exception 'post-check: a published study rule has no country applicability';
  end if;
  v_drift := security.consumer_api_check_v1();
  if jsonb_typeof(v_drift) = 'array' then
    if jsonb_array_length(v_drift) > 0 then raise exception 'consumer API drift %', v_drift; end if;
  elsif jsonb_array_length(coalesce(v_drift->'drift', '[]'::jsonb)) > 0 then raise exception 'consumer API drift %', v_drift->'drift';
  end if;
end $chk$;
