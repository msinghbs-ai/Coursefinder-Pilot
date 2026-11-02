-- CF-247 course link fill respects Layer 4 (Workstream E; Platform Admin direction 2 Nov 2026 23:24, admin
-- docs/platform/nz-enrichment-brief/2026-11-02-overnight-continuous-delivery-direction-2324.md §1-§3; housekeeping finding H05 in
-- 2026-11-02-housekeeping-disposition.md §6).
-- Why: the nightly fill (job course-url-fill, security.course_url_fill_v1, 13:23 AEDT) writes catalogue.courses.course_url from the course's
--   proven page binding. On 2 Nov 13:23 (event #28612) it wrote course_url on 25 courses whose page was already in a pending Layer 4 course-link
--   review (official_course_url): 17 raised the same morning by the E16 binding check (rule shared_page), 8 raised on 31 Oct by the coverage
--   sweep, each proposing the very page the fill then wrote. The fill pre-empted the reviewer, and the 25 joined housekeeping finding H05
--   (course_url differs from the shown link), which made the H05/H13/H20 routing file refuse at 16:06.
-- What:
--   1 Two settings (G2): course_url.fill_respects_layer4 (1 = leave a course alone while a Layer 4 course-link item is pending on it; 0 = the old
--     behaviour) and course_url.retraction_min_fills (the 30-day fill count below which the pause check is not applied; it was the number 50
--     written into the function, now a setting with the same value).
--   2 security.course_url_fill_v1 (md5-guarded edit, same name): with the switch on, a course with a pending official_course_url item is not
--     filled (first fill or re-fill). The run counts those courses (skipped_pending_layer4) in its return value and in its course_url_filled
--     event, which is now written when anything was skipped too. When the integration queue exists (security.integration_issue_upsert_v1,
--     branch cf247-integration-queue / migration 20261102120000), a run with skips records one queue issue by the deterministic fingerprint
--     'course-url-fill:skipped-pending-layer4' (P2, workstream A4, root cause human_decision): an unchanged problem updates that row; it never
--     makes a duplicate. A queue error never stops the fill (the error is in the return value).
--      Retractions (guard 3) are unchanged: a fill whose binding changes is still taken back. Nothing already filled is emptied by this change.
--   3 The job's catalogue note says the new rule (only when it still reads as written on 24 Oct).
-- Replaces: security.course_url_fill_v1 (md5-guarded edit, same name: the fill now waits for a pending Layer 4 course-link decision; the
--   pause threshold of 50 fills moves to a setting)
-- Retires: nothing
-- Nothing is dropped, deleted or switched off. No consumer API object changes (G3): course_url is not read by the consumer API, and no
-- function, table, column or edge function on the frozen list is touched.

create or replace function pg_temp.edit_once(p_sig text, p_before text, p_after text, p_edits text[][], p_times int[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_def) <> p_before then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
  if md5(pg_get_functiondef(p_sig::regprocedure)) <> p_after then
    raise exception '% after the edit has md5 %, expected %', p_sig, md5(pg_get_functiondef(p_sig::regprocedure)), p_after;
  end if;
  return p_sig || ': edited';
end $f$;

-- 1 settings (G2) ---------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'course_url.fill_respects_layer4', 'Official link: wait for Layer 4',
  '1 leaves a course''s link empty while a Layer 4 course-link review is pending on it, so the reviewer decides the page first; the nightly run counts the courses it left (skipped_pending_layer4). 0 fills them as before.',
  'number', '1'::jsonb, '0', '1', 'on/off', 604, 'Official link', 'job course-url-fill; security.course_url_fill_v1',
  'Platform Admin direction 2 Nov 2026 23:24 (Workstream E): the fill wrote pages still under Layer 4 review (event #28612)'),
 ('pipeline', 'course_url.retraction_min_fills', 'Official link: fills before the pause check',
  'The pause rule (Official link: most taken back) applies only once at least this many links were filled in the last 30 days.',
  'number', '50'::jsonb, '10', '1000', 'links', 605, 'Official link', 'security.course_url_fill_v1',
  'G2: was the number 50 written into security.course_url_fill_v1 (24 Oct 2026); same value')
on conflict (toolset_key, key) do nothing;

-- 2 the fill waits for a pending Layer 4 course-link decision ----------------------------------------------------------------------
select pg_temp.edit_once('security.course_url_fill_v1()', '9ae50ba49eea0a30ecd8da20eef7f97b', '270be3f52e98b58a1153b7c1170fd57e', array[
  array[$o$        v_rate jsonb; v_retracted int := 0; v_emptied int := 0; v_filled int := 0; v_refilled int := 0; v_by jsonb; v_now timestamptz := clock_timestamp();$o$,
        $n$        v_rate jsonb; v_retracted int := 0; v_emptied int := 0; v_filled int := 0; v_refilled int := 0; v_by jsonb; v_now timestamptz := clock_timestamp();
        -- Workstream E (Platform Admin 2 Nov 2026 23:24): a course with a pending Layer 4 course-link review is left for the reviewer
        v_respect boolean := security.pipeline_num_v1('course_url.fill_respects_layer4', 1) = 1;
        v_skipped int := 0; v_skip_ids uuid[] := '{}'; v_iq jsonb;$n$],
  array[$o$(v_rate->>'filled')::int >= 50 and$o$,
        $n$(v_rate->>'filled')::int >= security.pipeline_num_v1('course_url.retraction_min_fills', 50) and$n$],
  array[$o$  -- guards 1 and 2: fill empty links from proven bindings, in the countries allowed, never a locked course
  with f as ($o$,
        $n$  -- guard 5 (2 Nov 2026 23:24): count the courses that qualify but have a pending Layer 4 course-link review; they are not filled
  if v_respect then
    select count(*), coalesce(array_agg(c.id order by c.id), '{}') into v_skipped, v_skip_ids
      from catalogue.courses c
      join catalogue.providers pr on pr.id = c.provider_id
      join ref.countries k on k.id = pr.country_id
      join pipeline.coverage_course_pages p on p.course_id = c.id
     where c.lifecycle_status = 'active' and c.course_url is null
       and p.status = 'bound' and p.identity_basis is not null and p.read_status = 'read' and p.evidence_id is not null
       and coalesce(nullif(p.candidates->>'final_url', ''), p.url) ~* '^https?://'
       and security.coverage_identity_allowed(p.provider_id, p.identity_basis, 'official_url')
       and k.iso_alpha2 in (select jsonb_array_elements_text(s.value) from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'course_url.fill_countries')
       and not exists (select 1 from pipeline.manual_locks m where m.entity = 'course' and m.entity_id = c.id and m.field = 'course_url')
       and not exists (select 1 from pipeline.course_url_fills x where x.course_id = c.id and x.retracted_at is null)
       and c.id in (select i.entity_id from pipeline.layer4_review_items i
                     where i.entity_type = 'course' and i.field_code = 'official_course_url' and i.status = 'pending' and i.entity_id is not null);
  end if;
  -- guards 1 and 2: fill empty links from proven bindings, in the countries allowed, never a locked course
  with f as ($n$],
  array[$o$       and not exists (select 1 from pipeline.course_url_fills x where x.course_id = c.id and x.retracted_at is null)
     order by (k.iso_alpha2 = 'NZ') desc, c.id$o$,
        $n$       and not exists (select 1 from pipeline.course_url_fills x where x.course_id = c.id and x.retracted_at is null)
       and c.id not in (select i.entity_id from pipeline.layer4_review_items i
                         where v_respect and i.entity_type = 'course' and i.field_code = 'official_course_url' and i.status = 'pending' and i.entity_id is not null)
     order by (k.iso_alpha2 = 'NZ') desc, c.id$n$],
  array[$o$  if v_filled > 0 or v_retracted > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('catalogue', 'course_url_filled', 'courses.course_url',
            jsonb_build_object('filled', v_filled, 'refilled', v_refilled, 'by_country', v_by, 'retracted', v_retracted, 'emptied', v_emptied, 'batch', v_batch), null);
  end if;$o$,
        $n$  if v_skipped > 0 and to_regprocedure('security.integration_issue_upsert_v1(jsonb,text)') is not null then
    -- one integration-queue issue by fingerprint (an unchanged problem updates that row, never a duplicate); a queue error never stops the fill
    begin
      execute 'select security.integration_issue_upsert_v1($1, $2)' into v_iq
        using jsonb_build_object('fingerprint', 'course-url-fill:skipped-pending-layer4',
                'title', 'Course link fill waits for pending Layer 4 course-link reviews',
                'layer', 'Catalogue', 'subsystem', 'course-url-fill', 'workstream', 'A4', 'severity', 'P2', 'root_cause_class', 'human_decision',
                'validation_layer', 'V4', 'source', 'job course-url-fill',
                'failure', v_skipped || ' course(s) qualify for a course link from their proven page but have a pending Layer 4 course-link review, so the fill left them',
                'expected', 'Layer 4 decides the course page first; the next nightly fill writes the link once no course-link review is pending',
                'course_ids', to_jsonb(v_skip_ids),
                'evidence', jsonb_build_object('skipped_pending_layer4', v_skipped, 'run_at', v_now, 'setting', 'course_url.fill_respects_layer4')),
              'course-url-fill';
    exception when others then
      v_iq := jsonb_build_object('error', left(sqlerrm, 300));
    end;
  end if;
  if v_filled > 0 or v_retracted > 0 or v_skipped > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('catalogue', 'course_url_filled', 'courses.course_url',
            jsonb_build_object('filled', v_filled, 'refilled', v_refilled, 'by_country', v_by, 'retracted', v_retracted, 'emptied', v_emptied, 'batch', v_batch,
                               'skipped_pending_layer4', v_skipped, 'respects_layer4', v_respect, 'integration_queue', v_iq), null);
  end if;$n$],
  array[$o$  return jsonb_build_object('filled', v_filled, 'refilled', v_refilled, 'by_country', v_by, 'retracted', v_retracted, 'emptied', v_emptied, 'rate', v_rate);$o$,
        $n$  return jsonb_build_object('filled', v_filled, 'refilled', v_refilled, 'by_country', v_by, 'retracted', v_retracted, 'emptied', v_emptied, 'rate', v_rate,
                            'skipped_pending_layer4', v_skipped, 'respects_layer4', v_respect, 'integration_queue', v_iq);$n$]
], array[1, 1, 1, 1, 1, 1]);

comment on function security.course_url_fill_v1() is 'nightly: fills an empty course_url from the course''s proven own page (five guards: proven binding only, manual locks honoured, re-fill on binding change, pauses above the 30-day retraction limit, waits while a Layer 4 course-link review is pending (course_url.fill_respects_layer4)); NZ brief item 5 Option A; Workstream E 2 Nov 2026 23:24';

-- 3 the catalogue note (only if it still reads as written on 24 Oct) ---------------------------------------------------------------
update pipeline.automation_catalogue
   set description = description || ' Leaves a course alone while a Layer 4 course-link review is pending on it (Official link: wait for Layer 4) and counts those courses in its run note.'
 where jobname = 'course-url-fill' and description not like '%Official link: wait for Layer 4%'
   and description like 'Daily at 02:23 UTC: for courses with no official link%';

update pipeline.component_register set note = coalesce(note || '. ', '') || '3 Nov 2026 (20261103030000): waits for a pending Layer 4 course-link review', updated_at = now()
 where kind = 'function' and name = 'security.course_url_fill_v1' and coalesce(note, '') not like '%20261103030000%';

select 'course_url fill respects Layer 4: settings, guarded edit, catalogue note' ok;
