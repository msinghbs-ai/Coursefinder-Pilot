-- CF-247 F-SCH Admin UI (Platform Admin S2-Scholarship directive 13 Nov 2026 §6; Operating Model v1.19 S2-Scholarship 5): the Scholarships
-- Catalogue read gains the operator facts the directive lists, as optional columns and server-side filters (no new screen or dashboard):
--   round_state       open (a round closes today or later) | rolling | closed_recent (closed within sch_elig.readmit_round_stale_days) |
--                     stale_round (closed longer ago, nothing open, not rolling) | no_dates                         filter round_state
--   source_read_at    when the official page was last read                                                       filter source_stale
--                     (older than sch_detail.source_stale_days, 180, or never read)
--   named_courses / provider_wide_courses / derived_courses   course links by how they were made: the page names the course (page_named_course,
--                     explicit_course_scope), the page says every course (explicit_provider_scope), or derived from level and field
--                     (sweep_level_field_scope)                                                                     filter course_links
--   recovery_status   read | recovery_queued | recovery_failed | long_page_failed | queued | not_read (the version 3 detail reading and the
--                     long-page recovery of 20261113294100)                                                         filter recovery_status
--   website_v3        served (published, active, not held back by Layer 4) | blocked | not_served
--   status 'any'      lists every state, withdrawn (inactive) included; the default stays every state but inactive
-- Sorts: round (close date), source (last read), links (named course links).
-- Replaces: security.admin_scholarships_page(jsonb) (same name and signature; md5-guarded edits). Retires: nothing.

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values ('pipeline', 'sch_detail.source_stale_days', 'Scholarships Catalogue: a source read longer ago than this is stale',
        'The Scholarships Catalogue "Source stale" filter lists scholarships whose official page was last read longer ago than this, or never.',
        'number', '180'::jsonb, 7, 730, 'days', 1434, 'F-SCH 13 Nov 2026 (S2-Scholarship directive §6): source freshness in the catalogue', 'Scholarship details', 'security.admin_scholarships_page')
on conflict (toolset_key, key) do nothing;

select pg_temp.edit_n('security.admin_scholarships_page(jsonb)', 'c831f9f562ebb81d2bb56d088f50cdfb', array[
  array[$o$    mapped as (select m.scholarship_id, count(*)::int n from scholarship.course_mappings m where m.mapping_state = 'mapped' group by 1),$o$,
        $n$    -- 20261113304500: the same one scan of course_mappings also gives the links by how they were made
    mapped as (select m.scholarship_id, count(*)::int n,
                      count(*) filter (where m.mapping_basis in ('page_named_course', 'explicit_course_scope'))::int named_n,
                      count(*) filter (where m.mapping_basis = 'explicit_provider_scope')::int provider_n,
                      count(*) filter (where m.mapping_basis is null or m.mapping_basis not in ('page_named_course', 'explicit_course_scope', 'explicit_provider_scope'))::int derived_n
                 from scholarship.course_mappings m where m.mapping_state = 'mapped' group by 1),$n$],
  array[$o$    v3r as materialized (select distinct x.scholarship_id from pipeline.scholarship_ai_extractions x where x.prompt_version >= 3 and x.error is null and x.scholarship_id is not null),$o$,
        $n$    v3r as materialized (select distinct x.scholarship_id from pipeline.scholarship_ai_extractions x where x.prompt_version >= 3 and x.error is null and x.scholarship_id is not null),
    -- 20261113304500: operator facts (round, source freshness, course link basis, detail recovery, Website v3)
    srd as (select sp.scholarship_id, max(sp.read_at) read_at from pipeline.scholarship_pages sp group by 1),
    owin as (select distinct w.scholarship_id from scholarship.application_windows w where w.closes_at >= current_date),
    rq as (select q.scholarship_id, bool_or(q.recovery is not null and q.state in ('queued', 'leased')) rec_open,
                  bool_or(q.recovery is not null and q.state not in ('queued', 'leased')) rec_done,
                  bool_or(q.recovery is null and q.state in ('queued', 'leased') and q.run_kind in ('detail', 'reread')) other_open
             from pipeline.scholarship_ai_queue q where q.scholarship_id is not null and q.prompt_version >= 3 group by 1),
    lpf as materialized (select distinct x.scholarship_id from pipeline.scholarship_ai_extractions x where x.prompt_version >= 3 and x.scholarship_id is not null
                          and (x.error like 'held_partial: output_truncated%' or x.error like 'no_answer%' or x.error like 'unreadable_answer%')),
    blk as (select distinct b.scholarship_id from security.layer4_search_blocked_scholarships b),$n$],
  array[$o$        (v3.scholarship_id is not null) detail_read, length(coalesce(s.description, '')) >= 80 has_description$o$,
        $n$        (v3.scholarship_id is not null) detail_read, length(coalesce(s.description, '')) >= 80 has_description,
        case when ow.scholarship_id is not null or s.application_close_date >= current_date then 'open'
             when s.application_close_date is null then 'no_dates'
             when coalesce(ad.application_rolling, false) then 'rolling'
             when s.application_close_date >= current_date - security.pipeline_num_v1('sch_elig.readmit_round_stale_days', 365)::int then 'closed_recent'
             else 'stale_round' end round_state,
        sr.read_at source_read_at,
        coalesce(mp.named_n, 0) named_courses, coalesce(mp.provider_n, 0) provider_wide_courses, coalesce(mp.derived_n, 0) derived_courses,
        case when v3.scholarship_id is not null then 'read' when coalesce(rq.rec_open, false) then 'recovery_queued' when coalesce(rq.rec_done, false) then 'recovery_failed'
             when lp.scholarship_id is not null then 'long_page_failed' when coalesce(rq.other_open, false) then 'queued' else 'not_read' end recovery_status,
        case when bk.scholarship_id is not null then 'blocked' when s.publication_status = 'published' and s.lifecycle_status = 'active' then 'served' else 'not_served' end website_v3$n$],
  array[$o$      left join v3r v3 on v3.scholarship_id = s.id$o$,
        $n$      left join v3r v3 on v3.scholarship_id = s.id
      left join srd sr on sr.scholarship_id = s.id
      left join owin ow on ow.scholarship_id = s.id
      left join rq on rq.scholarship_id = s.id
      left join lpf lp on lp.scholarship_id = s.id
      left join blk bk on bk.scholarship_id = s.id$n$],
  array[$o$       where case when coalesce(p_args->>'status','') = '' then status <> 'inactive' else status = p_args->>'status' end$o$,
        $n$       where case when coalesce(p_args->>'status','') = '' then status <> 'inactive' when p_args->>'status' = 'any' then true else status = p_args->>'status' end
         and (nullif(p_args->>'round_state','') is null or round_state = p_args->>'round_state')
         and (nullif(p_args->>'course_links','') is null or case p_args->>'course_links'
               when 'named' then named_courses > 0 when 'provider_wide' then provider_wide_courses > 0
               when 'derived_only' then derived_courses > 0 and named_courses = 0 and provider_wide_courses = 0
               when 'none' then named_courses + provider_wide_courses + derived_courses = 0 else true end)
         and (nullif(p_args->>'recovery_status','') is null or recovery_status = p_args->>'recovery_status')
         and (nullif(p_args->>'source_stale','') is null
              or (source_read_at is null or source_read_at < now() - make_interval(days => security.pipeline_num_v1('sch_detail.source_stale_days', 180)::int)) = (p_args->>'source_stale')::boolean)$n$],
  array[$o$        case when v_sort='method' and v_dir='desc' then coalesce(application_method,'') end desc,$o$,
        $n$        case when v_sort='method' and v_dir='desc' then coalesce(application_method,'') end desc,
        case when v_sort='round' and v_dir='asc' then application_close_date end asc nulls last,
        case when v_sort='round' and v_dir='desc' then application_close_date end desc nulls last,
        case when v_sort='source' and v_dir='asc' then source_read_at end asc nulls first,
        case when v_sort='source' and v_dir='desc' then source_read_at end desc nulls last,
        case when v_sort='links' and v_dir='asc' then named_courses end asc,
        case when v_sort='links' and v_dir='desc' then named_courses end desc,$n$]
], array[1, 1, 1, 1, 1, 1]);
