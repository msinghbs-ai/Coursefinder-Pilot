// AU catalogue export fixtures: prints the fixture schema. The tables the export reads are taken verbatim (CREATE TABLE blocks) from the
// live schema baseline (supabase/live-capture/baseline/schema.sql); the two entry tables created after the baseline are taken from their
// migration (20261026001000, columns of 20261026007000), without foreign keys. Views and functions the export reads are small stand-ins.
import fs from 'node:fs'
const root = new URL('../../../supabase/', import.meta.url)
const base = fs.readFileSync(new URL('live-capture/baseline/schema.sql', root), 'utf8')
const mig = fs.readFileSync(new URL('migrations/20261026001000_cf247_entry_matrix_step_a.sql', root), 'utf8')
const table = (sql, name) => {
  const a = sql.indexOf(`CREATE TABLE IF NOT EXISTS ${name} (`); if (a < 0) throw new Error(`not in baseline: ${name}`)
  return sql.slice(a, sql.indexOf('\n);', a) + 3)
}
const T = ['"catalogue"."courses"', '"catalogue"."providers"', '"catalogue"."course_fees"', '"catalogue"."course_intakes"', '"catalogue"."course_english_requirements"',
  '"catalogue"."course_links"', '"catalogue"."course_campuses"', '"catalogue"."campuses"', '"catalogue"."provider_rankings"', '"catalogue"."course_identifiers"',
  '"search"."course_documents"', '"search"."enrichment_gates"', '"search"."enrichment_source_gates"', '"search"."projection_country_gates"',
  '"pipeline"."sources"', '"pipeline"."coverage_course_pages"', '"pipeline"."layer4_review_items"',
  '"scholarship"."scholarships"', '"scholarship"."course_mappings"', '"scholarship"."course_financial_calculations"', '"scholarship"."award_tiers"', '"scholarship"."criteria"',
  '"scholarship"."criterion_groups"', '"scholarship"."application_windows"', '"scholarship"."offering_cycles"', '"scholarship"."identifiers"',
  '"ref"."countries"', '"ref"."study_levels"', '"ref"."fields_of_study"', '"ref"."subdivisions"', '"ref"."english_tests"', '"ref"."ranking_sources"']
const out = [`create schema catalogue; create schema search; create schema pipeline; create schema scholarship; create schema ref; create schema security; create schema extensions; create schema cron;
create function extensions.gen_random_uuid() returns uuid language sql as 'select gen_random_uuid()';`]
for (const t of T) out.push(table(base, t))
const entry = (name) => { const a = mig.indexOf(`create table ${name} (`); return mig.slice(a, mig.indexOf('\n);', a) + 3).replace(/ references [a-z_.]+\([a-z_]+\)/g, '') }
out.push(entry('catalogue.provider_entry_matrix'), entry('catalogue.course_entry_requirements'))
out.push(`alter table catalogue.provider_entry_matrix add column routes jsonb, add column valid_to date, add column withdrawal_reason varchar(500), add column row_hash char(64), add column version integer default 1, add column aer_level varchar(20);
create table security.layer4_active_blocks (entity_type text, entity_id uuid, block_scope text);
create view security.layer4_search_blocked_courses as select entity_id as course_id from security.layer4_active_blocks where block_scope = 'search' and entity_type = 'course'
  union select c.id from security.layer4_active_blocks b join catalogue.courses c on c.provider_id = b.entity_id where b.block_scope = 'search' and b.entity_type = 'provider';
create view security.layer4_search_blocked_scholarships as select entity_id as scholarship_id from security.layer4_active_blocks where block_scope = 'search' and entity_type = 'scholarship';
create function security.region_fallback_countries_v1() returns text[] language sql stable as $$ select array['CA'] $$;
create table cron.job (jobid bigserial, jobname text, schedule text, active boolean default true);
create table cron.job_run_details (runid bigserial, status text, return_message text, start_time timestamptz);`)
process.stdout.write(out.join(';\n\n').replace(/;;/g, ';') + ';\n')
