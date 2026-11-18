-- CF-247 28-destination schema lock: the CHECK constraints of paste file v2 applied as a migration (S2-Build; Platform Admin 18 Nov 2026
-- 14:23: "Apply docs/paste/PASTE-20261118-29-destination-check-constraints.sql (v2)" as the sole migration lane before the Thursday freeze).
--
-- Source: admin docs/paste/PASTE-20261118-29-destination-check-constraints.sql v2 (md5 22bc38a31482375b8da67e214fd73939), whose rolled-back live
-- dry run passed at head 20261118150000 (probe Pilot #1271). The body below is that file's, without its own begin/commit and read-back, and with
-- the audit row's actor left null (a migration runs without a signed-in user). Each constraint is still replaced only if its live definition
-- is the one read on 18 Nov. Relaxing a CHECK constraint drops and re-adds it: the paste file existed for that reason (drops go to the Platform
-- Admin); the Platform Admin directed at 14:23 that it be applied. Every new definition accepts everything the old one did, so no row is
-- rejected and nothing else is dropped.
-- Consumer API change approved: Platform Admin, 18 Nov 2026 12:21 AEDT ("Allow Financial Times (FT) in the ranking system constraint"); applied by direction of 14:23 AEDT: ranking.systems is a frozen consumer API relation; only its code CHECK changes, no column is added, dropped, renamed or retyped, so the column baseline (G3, 75 functions and 48 relations) is unchanged.
-- Replaces: the six definitions read on 18 Nov (occupation schemes ANZSCO, NOC, SOC; state codes ^[A-Z]{2,3}$; six study-rule categories;
--           accreditation bodies AACSB, EQUIS, AMBA; ranking systems qs_wur, the_wur, arwu; occupation fields not null on every career row).
-- Retires: nothing.


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
                           'consumer_api_change_approved', 'Platform Admin 18 Nov 2026 12:21: ft in ranking.systems', 'applied_by', 'migration 20261118165000 (Platform Admin 14:23)'), null);

do $e$
begin
  if (select count(*) from security.consumer_api_functions_v1()) <> 75 or (select count(*) from security.consumer_api_relations_v1()) <> 48 then
    raise exception 'G3: the consumer API surface changed';
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'destination.study_rules'::regclass and conname = 'study_rules_rule_category_check'
                  and pg_get_constraintdef(oid) like '%offer_document%') then
    raise exception 'the study rule categories were not replaced';
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'ranking.systems'::regclass and contype = 'c' and pg_get_constraintdef(oid) like '%''ft''%') then
    raise exception 'the ranking system code check was not replaced';
  end if;
end $e$;
