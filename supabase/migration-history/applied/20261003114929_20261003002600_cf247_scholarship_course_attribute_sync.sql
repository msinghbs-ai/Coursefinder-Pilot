-- CF-247 (3 Oct 2026, 22:45 AEST). Decision 247, part 2. Publishing, withdrawing, a changed value or a changed saving
-- did not reach a course's scholarship attribute (search.course_documents.scholarship_options, read by search, the
-- website and Zoho): nothing re-projected it. Job scholarship-course-attribute now keeps it in step:
--   * every 15 minutes, the courses linked to any scholarship changed since the last run (record updated, published or
--     withdrawn, saving recalculated), plus courses that show a scholarship no longer linked to them;
--   * nightly at 06:51 AEST (after the 06:17 publication review and the 06:41 savings run), every course that has a
--     decided scholarship link or shows a scholarship today — a full sweep (about 20 seconds).
-- The projection itself is the existing scoped refresh (Decision 247 part 1 decides what it holds).
create table if not exists pipeline.scholarship_attribute_sync(
  id int primary key default 1 check (id = 1), last_run_at timestamptz not null default '-infinity', last_result jsonb);
insert into pipeline.scholarship_attribute_sync(id) values (1) on conflict (id) do nothing;
revoke all on pipeline.scholarship_attribute_sync from public, anon, authenticated;

create or replace function security.scholarship_course_attribute_sync_v1(p_full boolean default false)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog', 'scholarship', 'pipeline', 'search', 'security' as $f$
declare v_since timestamptz; v_now timestamptz := now(); v_ids uuid[]; v_res jsonb; v_done int := 0; v_batch uuid[]; i int := 0;
begin
  select last_run_at into v_since from pipeline.scholarship_attribute_sync where id = 1;
  if p_full then
    select array_agg(distinct x) into v_ids from (
      select course_id x from scholarship.course_mappings where mapping_state = 'mapped'
      union select d.course_id from search.course_documents d where coalesce(jsonb_array_length(d.scholarship_options), 0) > 0) q;
  else
    select array_agg(distinct x) into v_ids from (
      select m.course_id x from scholarship.course_mappings m join scholarship.scholarships s on s.id = m.scholarship_id where s.updated_at > v_since
      union select fc.course_id from scholarship.course_financial_calculations fc where fc.calculated_at > v_since
      union select m.course_id from scholarship.course_mappings m join pipeline.scholarship_publication_batches b on m.scholarship_id = any(b.scholarship_ids) where b.created_at > v_since
      union select m.course_id from scholarship.course_mappings m where m.updated_at > v_since) q;
  end if;
  v_ids := coalesce(v_ids, '{}');
  while i * 2000 < cardinality(v_ids) loop
    v_batch := v_ids[i * 2000 + 1 : (i + 1) * 2000];
    v_res := search.refresh_course_enrichment_core_scoped_v1(v_batch, true);
    v_done := v_done + coalesce((v_res->>'changed')::int, 0);
    i := i + 1;
  end loop;
  v_res := jsonb_build_object('full', p_full, 'courses', cardinality(v_ids), 'changed', v_done, 'since', v_since);
  update pipeline.scholarship_attribute_sync set last_run_at = v_now, last_result = v_res where id = 1;
  return v_res;
end $f$;
revoke all on function security.scholarship_course_attribute_sync_v1(boolean) from public, anon, authenticated;

select cron.schedule('scholarship-course-attribute', '*/15 * * * *', $$select security.scholarship_course_attribute_sync_v1(false)$$);
select cron.schedule('scholarship-course-attribute-full', '51 20 * * *', $$select security.scholarship_course_attribute_sync_v1(true)$$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable)
values ('scholarship-course-attribute', 'Scholarships', 74, 'Course scholarship attribute',
        'Every 15 minutes: refreshes the scholarships shown on each course (search, website, Zoho) for courses linked to a scholarship that was changed, published, withdrawn or re-costed since the last run (Decision 247).', 5, false),
       ('scholarship-course-attribute-full', 'Scholarships', 75, 'Course scholarship attribute (nightly sweep)',
        'Nightly at 06:51 AEST, after the publication review and the savings run: refreshes the scholarships shown on every course that has a scholarship link or shows one (Decision 247).', 5, false)
on conflict (jobname) do nothing;

select security.scholarship_course_attribute_sync_v1(true);
