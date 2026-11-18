-- PROBE ONLY (never merged): rolled-back live dry run of admin paste file PASTE-20261118-29-destination-check-constraints.sql v2, begin/commit removed.
-- Replaces: nothing.
-- Retires: nothing.
-- PASTE-20261118-29-destination-check-constraints.sql (version 2, 18 Nov 2026 12:40 AEDT; version 1 never run)
-- CF-247 29-destination readiness (S2-Build; Platform Admin 18 Nov 2026 11:28). For the Platform Admin to run in the Supabase SQL editor of
-- fxcwkweaxjtknorudmwp BEFORE Thursday 19 Nov 2026 01:15 AEDT (migration freeze; the canonical squash then captures the relaxed constraints).
-- Why a paste file: relaxing a CHECK constraint drops and re-adds it, and drops go to the Platform Admin (Pilot CLAUDE.md).
--
-- Read live 18 Nov 2026 11:40 AEDT, three constraints reject valid values for destinations beyond AU, CA, GB, NZ and US:
--   1. destination.career_outcomes.occupation_scheme allows only ANZSCO, NOC and SOC. The EU, Nordic and Asian destinations publish occupations
--      in ISCO-08 / ESCO or a national scheme (Germany KldB, France ROME, Sweden SSYK, Denmark DISCO, Singapore SSOC, Malaysia MASCO,
--      Korea KSCO, Japan JSCO, Thailand TSCO).
--   2. destination.career_outcomes.state_code must match ^[A-Z]{2,3}$. ISO 3166-2 subdivision codes are numeric in Japan, Korea, Thailand,
--      Malaysia, Singapore, Poland, Finland, Denmark, Austria, Cyprus and Latvia (for example JP-13, KR-11, FI-18, LV-011).
--   3. destination.study_rules.rule_category allows application_route, visa_funds, work_rights, post_study_work, visa_fee and processing_time.
--      Health insurance (Australia OSHC; statutory cover in Germany and the Netherlands), English or language requirements and admission tests
--      (Study Square ruling of 13 Nov: admission tests as a general note) have no category. Added here; remove any you do not want before running.
-- Version 2 adds the Platform Admin's 12:21 values: study rule categories dependants, minimum_wage, offer_document; occupation schemes OSCA
-- (Australia, replacing ANZSCO) and NOL (New Zealand); ranking system ft (Financial Times); accreditation bodies TEF, NZQA_EER, TRUSTED, KHDA,
-- SETARA, IEQAS, FINEEC, ANVUR (national quality ratings, grade in the new column rating); and occupation fields left empty on industry rows.
-- RUN ORDER: after Pilot migration 20261118150000 (career_outcomes.series_kind) is live; the file stops otherwise.
-- Consumer API change approved: Platform Admin, 18 Nov 2026 12:21 AEDT ("Allow Financial Times (FT) in the ranking system constraint"):
-- ranking.systems is a frozen consumer API relation; only its code CHECK changes, no column is added, dropped, renamed or retyped.
-- Each constraint is replaced only if its live definition is still the one read above; the new definitions accept everything the old ones did.
-- Nothing else is changed. Read back at the end.


do $$
declare v text;
begin
  select pg_get_constraintdef(oid) into v from pg_constraint where conrelid = 'destination.career_outcomes'::regclass and conname = 'career_outcomes_occupation_scheme_check';
  if v <> 'CHECK (((occupation_scheme IS NULL) OR (occupation_scheme = ANY (ARRAY[''ANZSCO''::text, ''NOC''::text, ''SOC''::text]))))' then
    raise exception 'career_outcomes_occupation_scheme_check is not the definition read on 18 Nov: %', v;
  end if;
  select pg_get_constraintdef(oid) into v from pg_constraint where conrelid = 'destination.career_outcomes'::regclass and conname = 'career_outcomes_state_code_check';
  if v <> 'CHECK (((state_code IS NULL) OR (state_code ~ ''^[A-Z]{2,3}$''::text)))' then
    raise exception 'career_outcomes_state_code_check is not the definition read on 18 Nov: %', v;
  end if;
  select pg_get_constraintdef(oid) into v from pg_constraint where conrelid = 'destination.study_rules'::regclass and conname = 'study_rules_rule_category_check';
  if v <> 'CHECK (((rule_category IS NULL) OR (rule_category = ANY (ARRAY[''application_route''::text, ''visa_funds''::text, ''work_rights''::text, ''post_study_work''::text, ''visa_fee''::text, ''processing_time''::text]))))' then
    raise exception 'study_rules_rule_category_check is not the definition read on 18 Nov: %', v;
  end if;
  select pg_get_constraintdef(oid) into v from pg_constraint where conrelid = 'catalogue.provider_accreditations'::regclass and conname = 'provider_accreditations_body_code_check';
  if v <> 'CHECK ((body_code = ANY (ARRAY[''AACSB''::text, ''EQUIS''::text, ''AMBA''::text])))' then
    raise exception 'provider_accreditations_body_code_check is not the definition read on 18 Nov: %', v;
  end if;
  select pg_get_constraintdef(oid) into v from pg_constraint where conrelid = 'ranking.systems'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%code = ANY%';
  if v <> 'CHECK ((code = ANY (ARRAY[''qs_wur''::text, ''the_wur''::text, ''arwu''::text])))' then
    raise exception 'ranking.systems code check is not the definition read on 18 Nov: %', v;
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'destination.career_outcomes'::regclass and conname = 'career_outcomes_series_fields_check') then
    raise exception 'run Pilot migration 20261118150000 first (career_outcomes.series_kind and its checks)';
  end if;
end $$;

alter table destination.career_outcomes drop constraint career_outcomes_occupation_scheme_check;
alter table destination.career_outcomes add constraint career_outcomes_occupation_scheme_check
  check (occupation_scheme is null or occupation_scheme = any (array['ANZSCO','OSCA','NOL','NOC','SOC','ISCO','ESCO','KLDB','ROME','SSYK','DISCO','SSOC','MASCO','KSCO','JSCO','TSCO']));

alter table destination.career_outcomes drop constraint career_outcomes_state_code_check;
alter table destination.career_outcomes add constraint career_outcomes_state_code_check
  check (state_code is null or state_code ~ '^[A-Z0-9]{1,3}$');

alter table destination.study_rules drop constraint study_rules_rule_category_check;
alter table destination.study_rules add constraint study_rules_rule_category_check
  check (rule_category is null or rule_category = any (array['application_route','visa_funds','work_rights','post_study_work','visa_fee','processing_time',
                                                             'health_insurance','language_requirement','admission_test','dependants','minimum_wage','offer_document']));

alter table catalogue.provider_accreditations drop constraint provider_accreditations_body_code_check;
alter table catalogue.provider_accreditations add constraint provider_accreditations_body_code_check
  check (body_code = any (array['AACSB','EQUIS','AMBA','TEF','NZQA_EER','TRUSTED','KHDA','SETARA','IEQAS','FINEEC','ANVUR']));

do $$
declare v_name text := (select conname from pg_constraint where conrelid = 'ranking.systems'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%code = ANY%');
begin
  execute format('alter table ranking.systems drop constraint %I', v_name);
  execute format('alter table ranking.systems add constraint %I check (code = any (array[''qs_wur'',''the_wur'',''arwu'',''ft'']))', v_name);
end $$;

-- an industry row (series_kind industry) has no occupation; the series check added by Pilot 20261118150000 keeps occupation rows complete
alter table destination.career_outcomes alter column occupation_code drop not null;
alter table destination.career_outcomes alter column occupation_title drop not null;
alter table destination.career_outcomes alter column occupation_scheme drop not null;
do $$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'destination.career_outcomes'::regclass and conname = 'career_outcomes_occupation_fields_check') then
    alter table destination.career_outcomes add constraint career_outcomes_occupation_fields_check
      check (series_kind <> 'occupation' or (occupation_code is not null and occupation_title is not null and occupation_scheme is not null));
  end if;
end $$;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('destination', 'check_constraints_relaxed', '29-destination readiness',
        jsonb_build_object('paste_file', 'PASTE-20261118-29-destination-check-constraints.sql',
                           'constraints', jsonb_build_array('career_outcomes_occupation_scheme_check', 'career_outcomes_state_code_check', 'study_rules_rule_category_check',
                                                            'provider_accreditations_body_code_check', 'ranking.systems code check', 'career_outcomes occupation fields'),
                           'consumer_api_change_approved', 'Platform Admin 18 Nov 2026 12:21: ft in ranking.systems'), auth.uid());


