-- Helpers for the IQ-00116 fixture (session-local). A course has a search document, an evidence artefact on its source and a pending Layer 4
-- tuition item; approve() saves the decision the way the review desk does, calls the apply path and records the admission check.
create function pg_temp.u(k text) returns uuid language sql immutable as $f$ select md5(k)::uuid $f$;
create function pg_temp.ok(c boolean, m text) returns void language plpgsql as $f$
begin if c is not true then raise exception 'FAIL: %', m; end if; raise notice 'ok: %', m; end $f$;
create function pg_temp.course(k text, cc text, src text) returns void language plpgsql as $f$
begin
  insert into pipeline.sources(id, source_type, label) values (pg_temp.u('src ' || src), 'provider_course_page_sweep', src || ' course pages (coverage sweep)') on conflict do nothing;
  insert into catalogue.courses(id, course_code, lifecycle_status, duration_value, duration_unit) values (pg_temp.u(k), upper(replace(k, ' ', '')), 'active', 1, 'years');
  insert into search.course_documents(course_id, country_code) values (pg_temp.u(k), cc);
  insert into pipeline.evidence_artifacts(id, source_id, source_url) values (pg_temp.u('ev ' || k), pg_temp.u('src ' || src), 'https://provider.example/' || replace(k, ' ', '-'));
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, proposed_value, created_at)
  values (pg_temp.u('item ' || k), 'course', pg_temp.u(k), 'provider_current_tuition_validation', pg_temp.u('ev ' || k), '{}', now() - interval '7 days');
end $f$;
create function pg_temp.approve(k text, v jsonb, age interval) returns jsonb language plpgsql as $f$
declare r jsonb;
begin
  insert into pipeline.layer4_decisions(id, review_item_id, action, final_value, created_at) values (pg_temp.u('dec ' || k), pg_temp.u('item ' || k), 'approve', v, now() - age);
  r := security.layer4_tuition_apply_impl(null, pg_temp.u('item ' || k), v, '[fixture] approved');
  update pipeline.layer4_review_items set status = 'approved', decided_at = now() - age where id = pg_temp.u('item ' || k);
  perform security.layer4_admission_record_v1(pg_temp.u('dec ' || k));
  return r;
end $f$;
create function pg_temp.has_fee(k text) returns boolean language sql stable as $f$
  select coalesce(has_provider_current_tuition, false) from search.course_documents where course_id = pg_temp.u(k) $f$;
create function pg_temp.check_of(k text) returns text language sql stable as $f$
  select result || ':' || coalesce(reason, '') from pipeline.layer4_admission_checks where decision_id = pg_temp.u('dec ' || k) $f$;
create function pg_temp.cause(k text) returns text language plpgsql stable as $f$
begin return (select x.cause from security.tuition_publication_rows_v1(array[pg_temp.u(k)]) x); end $f$;
