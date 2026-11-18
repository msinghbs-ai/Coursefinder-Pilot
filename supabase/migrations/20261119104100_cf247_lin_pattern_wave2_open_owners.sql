-- CF-247 s719 follow-up (S2-Build; Platform Admin 19 Nov 2026 06:41, 06:45 and 06:50; scheduled check 19 Nov 10:10 AEDT).
--
-- What the 10:05 AEDT Layer 1 runs showed (read live 19 Nov 2026 10:10-10:20 AEDT):
--   * LIN 19/198 (legislation.gov.au, static read, passed): the fact was not found. The instrument's page text reads
--     "AUD29,710 ( primary applicant annual living costs )": the defined term is in italics, so the page text has a space inside each
--     bracket and the pattern of 20261119083100 did not allow one. No living-cost rule was written, so the published Home Affairs successor
--     holds 5 rules and no visa_funds rule.
--   * Home Affairs Step by step tab (student-500#HowTo, rendered read): Firecrawl returns the page without the tab's content, and the
--     nearest amount after "you" was AUD87,856 (the annual-income alternative), refused by the plausible maximum (40,000). Unchanged here:
--     the guard worked, and LIN 19/198 is the legal source of the amount.
--   * UKVI (GOV.UK, Open Government Licence v3.0) and USCIS (U.S. Government work, public domain) editions are drafts with approved terms,
--     evidence and quotes, but destination-open-licence-publish publishes only owners on destination.open_licence_owners, and neither owner
--     is on it. Immigration New Zealand stays held (terms pending).
-- What it changes (data only; no table, function or job; the consumer API is not touched, G3 75/48):
--   1. The LIN 19/198 fact pattern allows spaces inside the brackets; LIN 19/198 is due at the next Layer 1 tick (hourly at :05).
--   2. destination.open_licence_owners adds 'UK Visas and Immigration (Home Office)' and 'U.S. Citizenship and Immigration Services'
--      (Platform Admin 19 Nov 2026 06:45: next wave, approve open terms and publish).
-- Replaces: the LIN 19/198 fact pattern of 20261119083100.
-- Retires: nothing.

-- 1. LIN 19/198 pattern: a space may stand inside each bracket (the defined term is set in italics on the page)
do $p$
declare v_n int;
begin
  update destination.page_facts
     set pattern = 'AUD\s?([0-9]{2},[0-9]{3})\s*\(\s*primary applicant annual living costs\s*\)',
         note = coalesce(note, '') || ' | 19 Nov 2026 (20261119104100, s719): a space may stand inside each bracket (italic defined term)',
         updated_at = now()
   where page_url like 'https://www.legislation.gov.au/F2019L01366/%' and rule_category = 'visa_funds'
     and pattern = 'AUD\s?([0-9]{2},[0-9]{3})\s*\(primary applicant annual living costs\)';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'LIN 19/198 fact: expected 1 row with the 20261119083100 pattern, found %', v_n; end if;
end $p$;

update pipeline.layer1_source_operations o
   set next_verification_at = now(), updated_at = now(),
       change_reason = 'Due 19 Nov 2026 (20261119104100, s719): fact pattern corrected (space inside the brackets); read again at the next tick'
  from pipeline.sources s
 where s.id = o.source_id and s.metadata->>'source_system' = 'DESTINATION'
   and o.authority_domains @> array['legislation.gov.au'] and o.active and not o.paused;

-- 2. open-licence owners for the next wave (GOV.UK OGL v3.0; U.S. Government work)
update pipeline.platform_toolset_settings s
   set value = s.value || (select coalesce(jsonb_agg(x), '[]'::jsonb)
                             from unnest(array['UK Visas and Immigration (Home Office)', 'U.S. Citizenship and Immigration Services']) x
                            where not s.value ? x),
       reason = 'Platform Admin 18 Nov 2026 13:07 (S2-Build): public CC BY and government open-data editions publish without manual clicks; QILT stays gated. '
             || '19 Nov 2026 06:45 (20261119104100, s719): next wave, UKVI (Open Government Licence v3.0) and USCIS (public domain) added; '
             || 'Immigration New Zealand waits for its terms',
       updated_at = now()
 where s.toolset_key = 'pipeline' and s.key = 'destination.open_licence_owners';

-- post-checks
do $c$
declare v_owners text[] := security.pipeline_list_v1('destination.open_licence_owners', '[]'::jsonb); v_n int;
begin
  if not v_owners @> array['UK Visas and Immigration (Home Office)', 'U.S. Citizenship and Immigration Services', 'Department of Home Affairs'] then
    raise exception 'open-licence owners are not as expected: %', v_owners;
  end if;
  if v_owners @> array['Immigration New Zealand (MBIE)'] then raise exception 'Immigration New Zealand must wait for its terms'; end if;
  select count(*) into v_n from pipeline.layer1_source_operations o
   where o.authority_domains @> array['legislation.gov.au'] and o.next_verification_at <= now() and o.active and not o.paused;
  if v_n <> 1 then raise exception 'LIN 19/198 is not due (% rows)', v_n; end if;
  if 'AUD29,710 ( primary applicant annual living costs )' !~* (select pattern from destination.page_facts
       where page_url like 'https://www.legislation.gov.au/F2019L01366/%' and rule_category = 'visa_funds') then
    raise exception 'LIN 19/198 pattern does not read the instrument text';
  end if;
end $c$;
