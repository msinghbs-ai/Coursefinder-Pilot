-- CF-247 API v3 destination editions: importer and publication guard (REQ-65, REQ-67, REQ-68; Platform Admin 15 Nov 2026 23:04, combined
-- build item 4, on the tables of 20261115190000_api_v3_additive_schema). Destination data is loaded only through governed editions:
--   1. uq_destination_editions_label: one edition per country, domain and label, so an import of the same edition is idempotent.
--   2. security.destination_edition_guard_v1 (trigger on destination.editions): no edition reaches status 'published' unless its
--      terms_status is 'approved' (REQ-68: terms of use confirmed before anything is republished). Enforced on every insert and update,
--      whoever writes.
--   3. security.destination_row_guard_v1 (trigger on study_rules, city_profiles, career_outcomes): rows of a published or superseded edition
--      are fixed (a change is a new edition); a row's country is its edition's country; a row belongs to the table of its edition's domain.
--   4. security.destination_import_v1(payload): idempotent import of one edition and its rows. The edition is matched by country (ISO
--      alpha-2, resolved to ref.countries), domain and label; a new edition starts as 'draft' with terms 'pending' (or 'restricted' when the
--      payload says so; it never sets 'approved'); an existing draft or in_review edition has its source fields refreshed; a published or
--      superseded edition is refused. Rows are upserted on the tables' own unique keys and written only when a value changed. A city row
--      without city_id gets a stable id from its country and name (there is no canonical cities table yet). Returns the counts.
--   5. security.destination_edition_set_terms_v1(edition, terms, actor): records the terms decision. Taking a published edition's terms
--      away from 'approved' moves it to 'in_review' in the same write, so it leaves the API at once.
--   6. security.destination_edition_publish_v1(edition, actor): publishes a draft or in_review edition that has approved terms and at
--      least one row; the edition it replaces for the same country and domain becomes 'superseded' first (one published edition each).
-- Nothing is loaded here: the scope decision for REQ-65 and REQ-67 data and the terms decision for REQ-68 stay with the Platform Admin.
-- G1: no job. G2: no operational value. G3: no consumer object is read or changed (Website API v3 reads published editions in a later change).
-- Replaces: nothing.
-- Retires: nothing.

set local lock_timeout = '5s'; -- fixed: deploy-time safety (the destination tables are new and empty)

create unique index if not exists uq_destination_editions_label on destination.editions (country_id, domain, edition_label);

-- 2. Publication guard (REQ-68)
create or replace function security.destination_edition_guard_v1() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.status = 'published' and new.terms_status is distinct from 'approved' then
    raise exception using errcode = 'check_violation',
      message = format('DESTINATION_TERMS_NOT_APPROVED: edition %s cannot be published while its terms are %s (REQ-68)', new.id, new.terms_status);
  end if;
  return new;
end $$;

do $t$ begin
  if not exists (select 1 from pg_trigger where tgname = 'destination_edition_guard' and tgrelid = 'destination.editions'::regclass) then
    create trigger destination_edition_guard before insert or update on destination.editions
      for each row execute function security.destination_edition_guard_v1();
  end if;
end $t$;

-- 3. Row guard: published and superseded editions are fixed; country and domain follow the edition
create or replace function security.destination_row_guard_v1() returns trigger
language plpgsql set search_path = '' as $$
declare v_status text; v_country uuid; v_domain text;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    select e.status into v_status from destination.editions e where e.id = old.edition_id;
    if v_status in ('published', 'superseded') then
      raise exception using errcode = 'check_violation',
        message = format('DESTINATION_EDITION_FIXED: rows of a %s edition cannot change; import a new edition', v_status);
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  select e.status, e.country_id, e.domain into v_status, v_country, v_domain from destination.editions e where e.id = new.edition_id;
  if v_status in ('published', 'superseded') then
    raise exception using errcode = 'check_violation',
      message = format('DESTINATION_EDITION_FIXED: rows of a %s edition cannot change; import a new edition', v_status);
  end if;
  if new.country_id is distinct from v_country then
    raise exception using errcode = 'check_violation', message = 'DESTINATION_COUNTRY_MISMATCH: a row''s country must be its edition''s country';
  end if;
  if v_domain is distinct from tg_table_name then
    raise exception using errcode = 'check_violation',
      message = format('DESTINATION_DOMAIN_MISMATCH: edition domain %s does not hold %s rows', v_domain, tg_table_name);
  end if;
  return new;
end $$;

do $t$ begin
  if not exists (select 1 from pg_trigger where tgname = 'destination_row_guard' and tgrelid = 'destination.study_rules'::regclass) then
    create trigger destination_row_guard before insert or update or delete on destination.study_rules
      for each row execute function security.destination_row_guard_v1();
  end if;
end $t$;
do $t$ begin
  if not exists (select 1 from pg_trigger where tgname = 'destination_row_guard' and tgrelid = 'destination.city_profiles'::regclass) then
    create trigger destination_row_guard before insert or update or delete on destination.city_profiles
      for each row execute function security.destination_row_guard_v1();
  end if;
end $t$;
do $t$ begin
  if not exists (select 1 from pg_trigger where tgname = 'destination_row_guard' and tgrelid = 'destination.career_outcomes'::regclass) then
    create trigger destination_row_guard before insert or update or delete on destination.career_outcomes
      for each row execute function security.destination_row_guard_v1();
  end if;
end $t$;

-- 4. Importer
create or replace function security.destination_import_v1(p_payload jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  e jsonb := p_payload->'edition';
  v_cc text := upper(btrim(coalesce(e->>'country_code', '')));
  v_country uuid; v_domain text := btrim(coalesce(e->>'domain', '')); v_label text := btrim(coalesce(e->>'edition_label', ''));
  v_ed destination.editions%rowtype; v_new_edition boolean := false; v_edition_changed boolean := false;
  r jsonb; i int; v_ins int := 0; v_upd int := 0; v_total int := 0; v_was_insert boolean; v_city uuid;
  v_terms text := coalesce(nullif(btrim(e->>'terms_status'), ''), 'pending');
begin
  if jsonb_typeof(e) is distinct from 'object' then raise exception using errcode = '22023', message = 'INVALID_INPUT: edition must be an object'; end if;
  if p_payload ? 'rows' and jsonb_typeof(p_payload->'rows') <> 'array' then raise exception using errcode = '22023', message = 'INVALID_INPUT: rows must be a list'; end if;
  if v_domain not in ('study_rules', 'city_profiles', 'career_outcomes') then
    raise exception using errcode = '22023', message = 'INVALID_INPUT: domain must be study_rules, city_profiles or career_outcomes';
  end if;
  if v_label = '' then raise exception using errcode = '22023', message = 'INVALID_INPUT: edition_label is required'; end if;
  select c.id into v_country from ref.countries c where c.iso_alpha2 = v_cc;
  if v_country is null then raise exception using errcode = '22023', message = format('INVALID_INPUT: unknown country_code %s', v_cc); end if;
  if v_terms not in ('pending', 'restricted') then
    raise exception using errcode = '22023', message = 'INVALID_INPUT: an import sets terms_status pending or restricted; approval is a separate decision';
  end if;
  if nullif(btrim(e->>'source_url'), '') is null or nullif(btrim(e->>'source_owner'), '') is null or nullif(btrim(e->>'attribution_text'), '') is null
     or nullif(btrim(e->>'effective_from'), '') is null then
    raise exception using errcode = '22023', message = 'INVALID_INPUT: source_url, source_owner, attribution_text and effective_from are required';
  end if;

  select * into v_ed from destination.editions x where x.country_id = v_country and x.domain = v_domain and x.edition_label = v_label for update;
  if found then
    if v_ed.status in ('published', 'superseded') then
      raise exception using errcode = '22023',
        message = format('INVALID_INPUT: edition %s is %s and fixed; import it under a new edition_label', v_label, v_ed.status);
    end if;
    update destination.editions x set effective_from = (e->>'effective_from')::date, effective_to = nullif(e->>'effective_to', '')::date,
           source_url = btrim(e->>'source_url'), source_owner = btrim(e->>'source_owner'), attribution_text = btrim(e->>'attribution_text'),
           last_checked_at = now()
     where x.id = v_ed.id
       and (x.effective_from, x.effective_to, x.source_url, x.source_owner, x.attribution_text)
           is distinct from ((e->>'effective_from')::date, nullif(e->>'effective_to', '')::date, btrim(e->>'source_url'), btrim(e->>'source_owner'), btrim(e->>'attribution_text'));
    v_edition_changed := found;
  else
    insert into destination.editions(country_id, domain, edition_label, effective_from, effective_to, status, source_url, source_owner, attribution_text, terms_status)
    values (v_country, v_domain, v_label, (e->>'effective_from')::date, nullif(e->>'effective_to', '')::date, 'draft',
            btrim(e->>'source_url'), btrim(e->>'source_owner'), btrim(e->>'attribution_text'), v_terms)
    returning * into v_ed;
    v_new_edition := true;
  end if;

  for r, i in select x, o::int from jsonb_array_elements(coalesce(p_payload->'rows', '[]'::jsonb)) with ordinality t(x, o) loop
    v_total := v_total + 1;
    if jsonb_typeof(r) <> 'object' then raise exception using errcode = '22023', message = format('INVALID_INPUT: row %s is not an object', i); end if;
    begin
      if v_domain = 'study_rules' then
        insert into destination.study_rules as t(edition_id, country_id, visa_subclass, visa_name, application_fee_amount, fee_currency, financial_capacity_annual,
               work_hours_fortnight, work_hours_notes, post_study_work_years_min, post_study_work_years_max, processing_time_days_min, processing_time_days_max,
               application_channels, concessions, admission_tests_note, source_url)
        values (v_ed.id, v_country, btrim(r->>'visa_subclass'), btrim(r->>'visa_name'), (r->>'application_fee_amount')::numeric, upper(btrim(r->>'fee_currency')),
               (r->>'financial_capacity_annual')::numeric, (r->>'work_hours_fortnight')::int, r->>'work_hours_notes',
               (r->>'post_study_work_years_min')::numeric, (r->>'post_study_work_years_max')::numeric,
               (r->>'processing_time_days_min')::int, (r->>'processing_time_days_max')::int,
               coalesce(r->'application_channels', '[]'::jsonb), coalesce(r->'concessions', '{}'::jsonb), r->>'admission_tests_note',
               coalesce(nullif(btrim(r->>'source_url'), ''), v_ed.source_url))
        on conflict (edition_id, country_id, visa_subclass) do update set
               visa_name = excluded.visa_name, application_fee_amount = excluded.application_fee_amount, fee_currency = excluded.fee_currency,
               financial_capacity_annual = excluded.financial_capacity_annual, work_hours_fortnight = excluded.work_hours_fortnight,
               work_hours_notes = excluded.work_hours_notes, post_study_work_years_min = excluded.post_study_work_years_min,
               post_study_work_years_max = excluded.post_study_work_years_max, processing_time_days_min = excluded.processing_time_days_min,
               processing_time_days_max = excluded.processing_time_days_max, application_channels = excluded.application_channels,
               concessions = excluded.concessions, admission_tests_note = excluded.admission_tests_note, source_url = excluded.source_url,
               last_checked_at = now()
         where (t.visa_name, t.application_fee_amount, t.fee_currency, t.financial_capacity_annual, t.work_hours_fortnight, t.work_hours_notes,
                t.post_study_work_years_min, t.post_study_work_years_max, t.processing_time_days_min, t.processing_time_days_max,
                t.application_channels, t.concessions, t.admission_tests_note, t.source_url)
               is distinct from
               (excluded.visa_name, excluded.application_fee_amount, excluded.fee_currency, excluded.financial_capacity_annual, excluded.work_hours_fortnight,
                excluded.work_hours_notes, excluded.post_study_work_years_min, excluded.post_study_work_years_max, excluded.processing_time_days_min,
                excluded.processing_time_days_max, excluded.application_channels, excluded.concessions, excluded.admission_tests_note, excluded.source_url)
        returning (xmax = 0) into v_was_insert;
      elsif v_domain = 'city_profiles' then
        if nullif(btrim(r->>'city_name'), '') is null then raise exception using errcode = '22023', message = 'city_name is required'; end if;
        v_city := coalesce(nullif(r->>'city_id', '')::uuid, md5('city:' || v_cc || ':' || lower(btrim(r->>'city_name')))::uuid);
        insert into destination.city_profiles as t(edition_id, city_id, country_id, city_name, subdivision_code, population, population_year, population_source,
               climate_baseline, living_cost, cost_currency, source_url)
        values (v_ed.id, v_city, v_country, btrim(r->>'city_name'), nullif(btrim(r->>'subdivision_code'), ''), (r->>'population')::int, (r->>'population_year')::int,
               r->>'population_source', coalesce(r->'climate_baseline', '{}'::jsonb), coalesce(r->'living_cost', '{}'::jsonb), upper(btrim(r->>'cost_currency')),
               coalesce(nullif(btrim(r->>'source_url'), ''), v_ed.source_url))
        on conflict (edition_id, city_id) do update set
               city_name = excluded.city_name, subdivision_code = excluded.subdivision_code, population = excluded.population,
               population_year = excluded.population_year, population_source = excluded.population_source, climate_baseline = excluded.climate_baseline,
               living_cost = excluded.living_cost, cost_currency = excluded.cost_currency, source_url = excluded.source_url, last_checked_at = now()
         where (t.city_name, t.subdivision_code, t.population, t.population_year, t.population_source, t.climate_baseline, t.living_cost, t.cost_currency, t.source_url)
               is distinct from
               (excluded.city_name, excluded.subdivision_code, excluded.population, excluded.population_year, excluded.population_source,
                excluded.climate_baseline, excluded.living_cost, excluded.cost_currency, excluded.source_url)
        returning (xmax = 0) into v_was_insert;
      else
        insert into destination.career_outcomes as t(edition_id, country_id, occupation_code, occupation_title, study_area_code, skill_shortage_status, median_salary,
               salary_currency, salary_period, employment_rate_pct, job_outlook_rating, outlook_horizon_years, source_url)
        values (v_ed.id, v_country, btrim(r->>'occupation_code'), btrim(r->>'occupation_title'), nullif(btrim(r->>'study_area_code'), ''),
               nullif(btrim(r->>'skill_shortage_status'), ''), (r->>'median_salary')::numeric, upper(btrim(r->>'salary_currency')),
               coalesce(nullif(btrim(r->>'salary_period'), ''), 'annual'), (r->>'employment_rate_pct')::numeric, r->>'job_outlook_rating',
               (r->>'outlook_horizon_years')::int, coalesce(nullif(btrim(r->>'source_url'), ''), v_ed.source_url))
        on conflict (edition_id, country_id, occupation_code) do update set
               occupation_title = excluded.occupation_title, study_area_code = excluded.study_area_code, skill_shortage_status = excluded.skill_shortage_status,
               median_salary = excluded.median_salary, salary_currency = excluded.salary_currency, salary_period = excluded.salary_period,
               employment_rate_pct = excluded.employment_rate_pct, job_outlook_rating = excluded.job_outlook_rating,
               outlook_horizon_years = excluded.outlook_horizon_years, source_url = excluded.source_url, last_checked_at = now()
         where (t.occupation_title, t.study_area_code, t.skill_shortage_status, t.median_salary, t.salary_currency, t.salary_period, t.employment_rate_pct,
                t.job_outlook_rating, t.outlook_horizon_years, t.source_url)
               is distinct from
               (excluded.occupation_title, excluded.study_area_code, excluded.skill_shortage_status, excluded.median_salary, excluded.salary_currency,
                excluded.salary_period, excluded.employment_rate_pct, excluded.job_outlook_rating, excluded.outlook_horizon_years, excluded.source_url)
        returning (xmax = 0) into v_was_insert;
      end if;
    exception
      when check_violation or not_null_violation or invalid_text_representation or numeric_value_out_of_range or datetime_field_overflow
           or invalid_datetime_format or string_data_right_truncation or invalid_parameter_value then
        raise exception using errcode = '22023', message = format('INVALID_INPUT: row %s: %s', i, sqlerrm);
    end;
    if found then
      if v_was_insert then v_ins := v_ins + 1; else v_upd := v_upd + 1; end if;
    end if;
  end loop;

  return jsonb_build_object('edition_id', v_ed.id, 'country_code', v_cc, 'domain', v_domain, 'edition_label', v_label,
    'edition', case when v_new_edition then 'created' when v_edition_changed then 'updated' else 'unchanged' end,
    'status', (select x.status from destination.editions x where x.id = v_ed.id), 'terms_status', (select x.terms_status from destination.editions x where x.id = v_ed.id),
    'rows', v_total, 'inserted', v_ins, 'updated', v_upd, 'unchanged', v_total - v_ins - v_upd);
end $$;

-- 5. Terms decision
create or replace function security.destination_edition_set_terms_v1(p_edition uuid, p_terms text, p_actor uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v destination.editions%rowtype;
begin
  if p_terms not in ('approved', 'pending', 'restricted') then
    raise exception using errcode = '22023', message = 'INVALID_INPUT: terms must be approved, pending or restricted';
  end if;
  select * into v from destination.editions x where x.id = p_edition for update;
  if not found then raise exception using errcode = '22023', message = 'INVALID_INPUT: edition not found'; end if;
  update destination.editions x
     set terms_status = p_terms,
         status = case when x.status = 'published' and p_terms <> 'approved' then 'in_review' else x.status end,
         approved_by = case when p_terms = 'approved' then coalesce(p_actor, x.approved_by) else x.approved_by end
   where x.id = p_edition;
  return (select jsonb_build_object('edition_id', x.id, 'status', x.status, 'terms_status', x.terms_status) from destination.editions x where x.id = p_edition);
end $$;

-- 6. Publish (one published edition per country and domain)
create or replace function security.destination_edition_publish_v1(p_edition uuid, p_actor uuid default null) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare v destination.editions%rowtype; v_rows int; v_old uuid;
begin
  select * into v from destination.editions x where x.id = p_edition for update;
  if not found then raise exception using errcode = '22023', message = 'INVALID_INPUT: edition not found'; end if;
  if v.status not in ('draft', 'in_review') then
    raise exception using errcode = '22023', message = format('INVALID_INPUT: a %s edition cannot be published', v.status);
  end if;
  if v.terms_status is distinct from 'approved' then
    raise exception using errcode = 'check_violation',
      message = format('DESTINATION_TERMS_NOT_APPROVED: edition %s cannot be published while its terms are %s (REQ-68)', v.id, v.terms_status);
  end if;
  v_rows := case v.domain
    when 'study_rules' then (select count(*) from destination.study_rules r where r.edition_id = v.id)
    when 'city_profiles' then (select count(*) from destination.city_profiles r where r.edition_id = v.id)
    else (select count(*) from destination.career_outcomes r where r.edition_id = v.id) end;
  if v_rows = 0 then raise exception using errcode = '22023', message = 'INVALID_INPUT: an edition with no rows cannot be published'; end if;
  update destination.editions x set status = 'superseded',
         effective_to = case when x.effective_to is null and v.effective_from > x.effective_from then v.effective_from - 1 else x.effective_to end
   where x.country_id = v.country_id and x.domain = v.domain and x.status = 'published' and x.id <> v.id
  returning x.id into v_old;
  update destination.editions x set status = 'published', approved_by = coalesce(p_actor, x.approved_by), approved_at = now() where x.id = v.id;
  return jsonb_build_object('edition_id', v.id, 'status', 'published', 'rows', v_rows, 'superseded', v_old);
end $$;

revoke all on function security.destination_edition_guard_v1() from public, anon, authenticated;
revoke all on function security.destination_row_guard_v1() from public, anon, authenticated;
revoke all on function security.destination_import_v1(jsonb) from public, anon, authenticated;
revoke all on function security.destination_edition_set_terms_v1(uuid, text, uuid) from public, anon, authenticated;
revoke all on function security.destination_edition_publish_v1(uuid, uuid) from public, anon, authenticated;
grant execute on function security.destination_import_v1(jsonb) to service_role;
grant execute on function security.destination_edition_set_terms_v1(uuid, text, uuid) to service_role;
grant execute on function security.destination_edition_publish_v1(uuid, uuid) to service_role;

insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('function', 'security.destination_import_v1', 'Platform', 'Destination data', 'API v3 (REQ-65/67): idempotent import of one destination edition and its rows', 'active', '{}', '20261115230000'),
 ('function', 'security.destination_edition_publish_v1', 'Platform', 'Destination data', 'API v3 (REQ-68): publish a destination edition with approved terms; supersede the previous one', 'active', '{}', '20261115230000'),
 ('function', 'security.destination_edition_set_terms_v1', 'Platform', 'Destination data', 'API v3 (REQ-68): record the terms decision for a destination edition', 'active', '{}', '20261115230000'),
 ('function', 'security.destination_edition_guard_v1', 'Platform', 'Destination data', 'API v3 (REQ-68): no destination edition is published without approved terms (trigger)', 'active', '{}', '20261115230000'),
 ('function', 'security.destination_row_guard_v1', 'Platform', 'Destination data', 'API v3: rows of published or superseded destination editions are fixed (trigger)', 'active', '{}', '20261115230000')
on conflict do nothing;

-- Post-check: triggers in place, and the guard refuses a publish without approved terms (tried and rolled back)
do $check$
declare v_refused boolean := false; v_country uuid;
begin
  if (select count(*) from pg_trigger t where t.tgname in ('destination_edition_guard', 'destination_row_guard') and not t.tgisinternal) <> 4 then
    raise exception 'post-check: destination triggers';
  end if;
  select c.id into v_country from ref.countries c order by c.iso_alpha2 limit 1;
  if v_country is not null then
    begin
      insert into destination.editions(country_id, domain, edition_label, effective_from, status, source_url, source_owner, attribution_text, terms_status)
      values (v_country, 'study_rules', 'post-check', current_date, 'draft', 'https://example.invalid', 'post-check', 'post-check', 'pending');
      begin
        update destination.editions set status = 'published' where edition_label = 'post-check' and country_id = v_country and domain = 'study_rules';
      exception when check_violation then v_refused := true;
      end;
      raise exception using errcode = 'UE001', message = 'post-check rollback';
    exception when sqlstate 'UE001' then null;
    end;
    if not v_refused then raise exception 'post-check: an edition with pending terms was published'; end if;
    if exists (select 1 from destination.editions where edition_label = 'post-check') then raise exception 'post-check: test edition left behind'; end if;
  end if;
end $check$;
