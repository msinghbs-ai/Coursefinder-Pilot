create function pg_temp.ok(p boolean, p_what text) returns void language plpgsql as $f$
begin if p is not true then raise exception 'FAIL %', p_what; end if; end $f$;
create function pg_temp.u(p text) returns uuid language sql immutable as $f$ select md5(p)::uuid $f$;
create function pg_temp.y(p int) returns int language sql stable as $f$ select extract(year from (now() at time zone 'Australia/Melbourne'))::int + p $f$;
-- a course with its own proved page (bound, read, code in the address and the title), the page reader's stored intake wording for it (p_ctx),
-- and an intake row read from that page
create function pg_temp.course(p_key text, p_prov text, p_host text, p_code text, p_title text, p_ctx text default null) returns void language plpgsql as $f$
declare v_url text := 'https://www.' || p_host || '/study/' || lower(replace(p_title, ' ', '-')) || '-' || lower(p_code);
begin
  insert into catalogue.courses(id, provider_id, canonical_title, course_code, study_level_id)
  values (pg_temp.u(p_key), pg_temp.u(p_prov), p_title, p_code, (select id from ref.study_levels where code = 'masters_coursework'));
  insert into search.course_documents(course_id, country_code) values (pg_temp.u(p_key), 'AU');
  insert into pipeline.evidence_artifacts(id, storage_path, source_url) values (pg_temp.u('ev ' || p_key), 'snap/' || md5(p_key) || '.html.gz', v_url);
  alter table pipeline.coverage_course_pages disable trigger coverage_page_refused_host;
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, basis, status, read_status, identity_basis, evidence_id, candidates)
  values (pg_temp.u(p_key), pg_temp.u(p_prov), v_url, 'cricos_search', 'bound', 'read', 'cricos_code', pg_temp.u('ev ' || p_key),
          jsonb_build_object('page_title', p_title || ' (' || p_code || ') | ' || (select canonical_name from catalogue.providers where id = pg_temp.u(p_prov)), 'final_url', v_url)
          || case when p_ctx is null then '{}'::jsonb else jsonb_build_object('intake_context', jsonb_build_array(p_ctx)) end);
  alter table pipeline.coverage_course_pages enable trigger coverage_page_refused_host;
end $f$;
create function pg_temp.intake(p_key text, p_month text, p_year int default null, p_page text default null) returns uuid language sql as $f$
  insert into catalogue.course_intakes(course_id, intake_year, intake_label, status, source_id, evidence_id, confidence, source_intake_key)
  values (pg_temp.u(p_key), p_year, p_month, 'active', pg_temp.u('sweep'), pg_temp.u('ev ' || coalesce(p_page, p_key)), 1,
          p_key || ':' || coalesce(p_year::text, 'current') || ':' || lower(p_month)) returning id $f$;
create function pg_temp.row(p_key text, p_month text) returns catalogue.course_intakes language sql as $f$
  select * from catalogue.course_intakes where course_id = pg_temp.u(p_key) and intake_label = p_month and status = 'active' $f$;
create function pg_temp.rec(p_key text, p_month text) returns pipeline.course_intake_dates language sql as $f$
  select d.* from pipeline.course_intake_dates d join catalogue.course_intakes i on i.id = d.intake_id where i.course_id = pg_temp.u(p_key) and i.intake_label = p_month $f$;
create function pg_temp.switch(p_on boolean) returns void language sql as $f$
  update pipeline.platform_toolset_settings set value = to_jsonb(p_on) where toolset_key = 'pipeline' and key = 'intake_dates.apply_enabled' $f$;
