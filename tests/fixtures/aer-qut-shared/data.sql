-- fixture data (invented; nothing here is live data). Providers: P3 shared-page courses, P2 generic route cases, QUT-shaped provider with the live id.
create schema if not exists t;
insert into catalogue.providers(id, canonical_name) values ('00000000-0000-0000-0000-0000000000a3', 'Fixture shared-page university'), ('00000000-0000-0000-0000-0000000000a2', 'Fixture route university'),
  ('2c4f515c-c146-4e90-ba8a-294130aa1f40', 'Fixture QUT-shaped university');
insert into pipeline.platform_toolset_settings(toolset_key, key, label, kind, value, min_value, max_value, unit, used_by) values
  ('pipeline', 'aer.row_limit_matrix_rows', 'rows', 'number', '30'::jsonb, 6, 500, 'rows', 'fixture'),
  ('pipeline', 'entry.shared_page_hold', 'hold', 'number', '1'::jsonb, 0, 1, 'on/off', 'fixture'),
  ('pipeline', 'entry.variant_check', 'variant', 'number', '1'::jsonb, 0, 1, 'on/off', 'fixture');
-- shared-page courses: t.course(code, title, status, basis, url, locked)
create function t.course(p_prov uuid, p_title text, p_status text, p_basis text, p_url text, p_locked boolean default false) returns uuid language plpgsql as $f$
declare v uuid := gen_random_uuid();
begin
  insert into catalogue.courses(id, provider_id, canonical_title) values (v, p_prov, p_title);
  insert into pipeline.coverage_course_pages(course_id, provider_id, url, status, identity_basis) values (v, p_prov, p_url, p_status, p_basis);
  if p_locked then
    insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', v, 'official_url', 'value'), ('course', v, 'course_url', 'value');
  end if;
  return v;
end $f$;
create table t.named(name text primary key, id uuid);
do $d$
declare p uuid := '00000000-0000-0000-0000-0000000000a3';
begin
  insert into t.named values
   ('A1', t.course(p, 'Bachelor of Alpha', 'bound', 'cricos_code', 'https://x.test/u1')), ('B1', t.course(p, 'Bachelor of Beta', 'mismatch', null, 'https://x.test/u1')),
   ('A2', t.course(p, 'Bachelor of Gamma', 'bound', 'cricos_code', 'https://x.test/u2')), ('B2', t.course(p, 'Bachelor of Delta', 'bound', 'cricos_code', 'https://x.test/u2')),
   ('A3', t.course(p, 'Diploma of Epsilon (Level 5)', 'bound', 'nzqa_code', 'https://x.test/u3')), ('B3', t.course(p, 'Diploma of Zeta', 'ambiguous', 'exact_title', 'https://x.test/u3')),
   ('A4', t.course(p, 'Master of Eta', 'bound', 'cricos_code', 'https://x.test/u4', true)), ('B4', t.course(p, 'Master of Theta', 'mismatch', null, 'https://x.test/u4')),
   ('A5', t.course(p, 'Master of Iota', 'mismatch', null, 'https://x.test/u5')), ('B5', t.course(p, 'Master of Kappa', 'mismatch', null, 'https://x.test/u5')),
   ('A6', t.course(p, 'Certificate of Lambda', 'bound', 'manual', 'https://x.test/u6')), ('B6', t.course(p, 'Certificate of Mu', 'mismatch', null, 'https://x.test/u6')),
   ('A7', t.course(p, 'Certificate of Nu', 'bound', 'degree_name', 'https://x.test/u7')), ('B7', t.course(p, 'Certificate of Xi', 'mismatch', null, 'https://x.test/u7')),
   ('A8', t.course(p, 'Bachelor of Omicron', 'bound', 'exact_title', 'https://x.test/u8')), ('B8', t.course(p, 'Bachelor of Pi', 'mismatch', null, 'https://x.test/u8')),
   ('C8', t.course(p, 'Bachelor of Rho', 'mismatch', null, 'https://x.test/u8')),
   ('A9', t.course(p, 'Graduate Certificate in Sigma', 'bound', 'cricos_code', 'https://x.test/u9')), ('B9', t.course(p, 'Graduate Certificate in Sigma (Level 8)', 'mismatch', null, 'https://x.test/u9'));
end $d$;
-- route items: t.item(provider, title, cuts, mime, has_path, locked, status, url)
create function t.item(p_prov uuid, p_title text, p_cuts int, p_mime text, p_path boolean, p_locked boolean, p_status text, p_url text) returns uuid language plpgsql as $f$
declare c uuid := gen_random_uuid(); e uuid := gen_random_uuid(); i uuid := gen_random_uuid();
begin
  insert into catalogue.courses(id, provider_id, canonical_title) values (c, p_prov, p_title);
  insert into pipeline.evidence_artifacts(id, evidence_type, source_url, storage_path, content_hash, mime_type)
  values (e, 'source_snapshot', p_url, case when p_path then 'evidence/' || e end, md5(p_url), p_mime);
  insert into pipeline.layer4_review_items(id, entity_type, entity_id, field_code, evidence_id, proposed_value, status)
  values (i, 'course', c, 'course_entry_first_read', e,
          jsonb_build_object('url', p_url, 'rows', 6, 'dropped', (select coalesce(jsonb_agg(jsonb_build_object('kind', 'prior_qualification', 'quote', 'row ' || g, 'reason', 'over_row_limit')), '[]'::jsonb) from generate_series(1, p_cuts) g)),
          p_status);
  if p_locked then insert into pipeline.manual_locks(entity, entity_id, field, mode) values ('course', c, 'official_url', 'value'), ('course', c, 'course_url', 'value'); end if;
  return i;
end $f$;
do $d$
declare p2 uuid := '00000000-0000-0000-0000-0000000000a2'; q uuid := '2c4f515c-c146-4e90-ba8a-294130aa1f40'; k int; v uuid;
begin
  insert into t.named values
   ('i1', t.item(p2, 'Route one', 40, 'text/html', true, false, 'pending', 'https://r.test/one')),
   ('i2', t.item(p2, 'Route locked', 40, 'text/html', true, true, 'pending', 'https://r.test/locked')),
   ('i3', t.item(p2, 'Route short', 29, 'text/html', true, false, 'pending', 'https://r.test/short')),
   ('i4', t.item(p2, 'Route pdf', 40, 'application/pdf', true, false, 'pending', 'https://r.test/pdf')),
   ('i5', t.item(p2, 'Route decided', 40, 'text/html', true, false, 'approved', 'https://r.test/decided')),
   ('i6', t.item(p2, 'Route has source', 40, 'text/html', true, false, 'pending', 'https://r.test/hassource')),
   ('i7', t.item(p2, 'Route no copy', 40, 'text/html', false, false, 'pending', 'https://r.test/nocopy')),
   ('i8', t.item(p2, 'Route two', 31, 'text/html', true, false, 'pending', 'https://r.test/two')),
   ('i9', t.item(p2, 'Route three', 55, 'text/html', true, false, 'pending', 'https://r.test/three'));
  insert into pipeline.entry_matrix_sources(provider_id, url, found_via, status) values (p2, 'https://r.test/hassource', 'manual', 'found');
  -- QUT-shaped: 23 unlocked and 14 locked reads cut at 30 or more rows, one read cut at 8 rows
  for k in 1..23 loop insert into t.named values ('q' || k, t.item(q, 'QUT course ' || k, 30 + k, 'text/html', true, false, 'pending', 'https://q.test/c' || k)); end loop;
  for k in 24..37 loop insert into t.named values ('q' || k, t.item(q, 'QUT course ' || k, 30 + k, 'text/html', true, true, 'pending', 'https://q.test/c' || k)); end loop;
  insert into t.named values ('q38', t.item(q, 'QUT honours course', 8, 'text/html', true, false, 'pending', 'https://q.test/c38'));
end $d$;
insert into ref.countries(iso_alpha2) values ('AU');
