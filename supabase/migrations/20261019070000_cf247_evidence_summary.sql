-- CF-247 (19 Oct 2026). Platform Admin 19:04 (with a capture of the Evidence panel): "explain why the evidence details panel is so bloated
-- and hard to read ... how do we simplify evidence collection, readability and store them efficiently"; 20:33: "refresh plan for evidence,
-- plan and execute the next steps".
-- public.admin_evidence_summary(uuid): one short answer for the Evidence panel. What the saved page is, which course and provider it
-- belongs to, when and how it was read, whether it was accepted as that course's page and how (exact title, CRICOS code), whether it is
-- the page in use now, which values on the live record came from it (fees, intakes, English, links, campuses), open review items, and its
-- earlier and later copies. The technical details (hash, file, job) come in the same answer for a closed "Technical details" part.
-- It reads where today's course-page reader records things (the snapshot's own details, the course-page record and the catalogue's
-- evidence ids); the old panel read the retired observation and link model, so it showed "0 observations · 0 linked" for these pages.
-- Replaces: nothing (the old detail read, security.admin_evidence_detail, stays for other evidence types until the panel no longer uses it)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

CREATE OR REPLACE FUNCTION public.admin_evidence_summary(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare e pipeline.evidence_artifacts%rowtype; v_course uuid; v_key text; v_page record; v_obj record; v_src record; v_job record; v_supplied jsonb; v_lim int := 20;  -- fixed: values listed in the panel (the total is given)
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if security.current_role_rank() < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  select * into e from pipeline.evidence_artifacts where id = p_id;
  if e.id is null then return jsonb_build_object('error', 'not_found'); end if;

  v_course := case when coalesce(e.metadata->>'course_id', '') ~* '^[0-9a-f-]{36}$' then (e.metadata->>'course_id')::uuid end;
  if v_course is null then select g.course_id into v_course from pipeline.coverage_course_pages g where g.evidence_id = e.id limit 1; end if;
  if v_course is null then
    select x.course_id into v_course from (
      select course_id from catalogue.course_fees where evidence_id = e.id union all select course_id from catalogue.course_intakes where evidence_id = e.id
      union all select course_id from catalogue.course_english_requirements where evidence_id = e.id union all select course_id from catalogue.course_links where evidence_id = e.id) x limit 1;
  end if;
  select g.evidence_id, g.url, g.status, g.read_status, g.identity_basis into v_page from pipeline.coverage_course_pages g where g.course_id = v_course;
  select o.id, (o.metadata->>'size')::bigint size into v_obj from storage.objects o where o.bucket_id = 'evidence' and o.name = e.storage_path;
  select s.label, s.url, s.source_type into v_src from pipeline.sources s where s.id = e.source_id;
  select j.id, j.job_type, j.status into v_job from pipeline.jobs j where j.id = e.job_id;
  v_key := case when e.storage_path like 'layer2/%/coverage/%' then split_part(e.storage_path, '/', 5) end;

  with s as (
    select 'Fee' field, concat_ws(' ', f.currency_code, to_char(f.amount, 'FM999,999,990'), case f.basis when 'annual' then 'a year' when 'total_indicative' then 'whole course' else f.basis end, f.fee_year::text) val, f.status, 1 o from catalogue.course_fees f where f.evidence_id = e.id
    union all select 'Intake', coalesce(i.intake_label, to_char(i.start_date, 'DD Mon YYYY'), i.intake_year::text), i.status, 2 from catalogue.course_intakes i where i.evidence_id = e.id
    union all select 'English', concat_ws(' ', t.code, 'overall ' || r.overall_score::text, case when r.component_scores is not null and r.component_scores <> '{}'::jsonb then 'bands ' || (select string_agg(v.value, '/' order by v.key) from jsonb_each_text(r.component_scores) v) end), r.status, 3
      from catalogue.course_english_requirements r left join ref.english_tests t on t.id = r.english_test_id where r.evidence_id = e.id
    union all select 'Link: ' || replace(l.link_type, '_', ' '), l.url, l.status, 4 from catalogue.course_links l where l.evidence_id = e.id
    union all select 'Campus', c.name, null, 5 from catalogue.course_campuses cc join catalogue.campuses c on c.id = cc.campus_id where cc.evidence_id = e.id)
  select jsonb_build_object('total', count(*), 'items', coalesce((select jsonb_agg(jsonb_build_object('field', z.field, 'value', z.val, 'status', z.status) order by z.o, z.field, z.val)
                                                               from (select * from s order by o limit v_lim) z), '[]'::jsonb))
    into v_supplied from s;

  return jsonb_build_object(
    'id', e.id, 'evidence_type', e.evidence_type, 'captured_at', coalesce(e.captured_at, e.created_at),
    'page_url', e.source_url, 'source', case when v_src.label is not null then jsonb_build_object('label', v_src.label, 'url', v_src.url, 'type', v_src.source_type) end,
    'fetched_via', e.metadata->>'fetched_via', 'worker', e.metadata->>'worker',
    'course', (select jsonb_build_object('id', c.id, 'title', coalesce(c.display_title, c.canonical_title), 'code', c.course_code,
                 'provider', coalesce(p.display_name, p.canonical_name), 'provider_id', p.id)
                 from catalogue.courses c left join catalogue.providers p on p.id = c.provider_id where c.id = v_course),
    'accepted', case when v_course is null then null else jsonb_build_object(
                 'basis', coalesce(e.metadata->>'identity_basis', case when v_page.evidence_id = e.id then v_page.identity_basis end),
                 'in_use', v_page.evidence_id = e.id, 'page_now', v_page.url) end,
    'supplied', v_supplied,
    'reviews_open', (select count(*) from pipeline.layer4_review_items r where r.evidence_id = e.id and r.status not in ('approved', 'rejected', 'corrected', 'closed', 'resolved')),
    'copies', case when v_key is null then null else (select jsonb_build_object(
                 'earlier', count(*) filter (where coalesce(x.captured_at, x.created_at) < coalesce(e.captured_at, e.created_at)),
                 'later', count(*) filter (where coalesce(x.captured_at, x.created_at) > coalesce(e.captured_at, e.created_at)),
                 'newest_id', (array_agg(x.id order by coalesce(x.captured_at, x.created_at) desc) filter (where coalesce(x.captured_at, x.created_at) > coalesce(e.captured_at, e.created_at)))[1])
               from pipeline.evidence_artifacts x where x.evidence_type = e.evidence_type and x.storage_path like 'layer2/%/coverage/%' and split_part(x.storage_path, '/', 5) = v_key and x.id <> e.id) end,
    'file', jsonb_build_object('available', v_obj.id is not null, 'size_bytes', v_obj.size, 'mime_type', e.mime_type, 'content_hash', e.content_hash, 'storage_path', e.storage_path),
    'job', case when v_job.id is not null then jsonb_build_object('id', v_job.id, 'type', v_job.job_type, 'status', v_job.status) end);
end $function$;
revoke execute on function public.admin_evidence_summary(uuid) from public, anon;
grant execute on function public.admin_evidence_summary(uuid) to authenticated;

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'public.admin_evidence_summary', 'Operations', 'Evidence panel: what a saved page is, what it supplied, accepted how, copies', 'active', '20261019070000')
on conflict (kind, name) do nothing;
