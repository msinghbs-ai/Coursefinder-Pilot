-- CF-247 Decision 264 fix (17 Oct 2026), found checking the first run: 5 courses whose page names a level also print their own score for a test
-- of that level, and it differs (UWA Juris Doctor, Master of Education, Bachelor of Education (Primary) (Honours): IELTS 7.5 with "higher ELC
-- requirements" 7.0; JCU Bachelor of Pharmacy (Honours) 7.5 with Band 3a 7.0; JCU Exercise Science/Physiology 7.0 with Band 2 6.5). Their own
-- IELTS was kept, but the level's PTE, TOEFL and Cambridge were added, which mixes two standards. Now a course whose own score differs from the
-- level is not given the level, and the rows the level wrote for it are withdrawn (kept, not deleted). Its own reading stands.
-- Replaces: security.english_level_apply_v1 (md5-guarded)
-- Retires: nothing
-- Nothing dropped or deleted.

do $guard$
begin
  if md5(pg_get_functiondef('security.english_level_apply_v1(uuid,boolean)'::regprocedure)) <> '4c44713235dd2ee97867ca1e37bb9db1' then
    raise exception 'live security.english_level_apply_v1 differs from the definition this change replaces';
  end if;
end $guard$;

create or replace function security.english_level_apply_v1(p_provider_id uuid, p_apply boolean default true)
returns jsonb language plpgsql security definer set search_path = '' as $function$
declare x pipeline.provider_policy_proposals%rowtype; r record; v_lv jsonb; v_write jsonb; v_tests text[]; v_src uuid; v_name text; v_out int;
        v_written int := 0; v_same int := 0; v_own_differs int := 0; v_own int := 0; v_held int := 0; v_withdrawn int := 0; v_unknown jsonb := '{}'::jsonb;
        v_courses uuid[] := '{}'; v_err int := 0; v_last text; v_label text;
        v_day text := to_char(now() at time zone 'Australia/Melbourne', 'FMDD Mon YYYY');
begin
  -- the approved English policy in force that names levels (Decision 262 keeps one in force per level; the latest decision wins here)
  select * into x from pipeline.provider_policy_proposals
   where provider_id = p_provider_id and kind = 'english_policy' and status = 'approved' and jsonb_typeof(proposal->'levels') = 'object'
   order by decided_at desc nulls last limit 1;
  if x.id is null then return jsonb_build_object('skipped', 'no approved English policy with levels'); end if;
  if x.evidence_id is null or coalesce(x.content_hash, '') = '' then return jsonb_build_object('skipped', 'the policy page has no stored evidence'); end if;
  v_src := security.coverage_sweep_source(x.provider_id);
  select coalesce(p.display_name, p.canonical_name) into v_name from catalogue.providers p where p.id = x.provider_id;
  for r in
    select co.id course_id, g.url page_url, g.candidates->'adapter_extra'->>'english_level' raw,
           security.english_level_key(g.candidates->'adapter_extra'->>'english_level') k,
           exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = co.id and l.field in ('english', 'english_requirements', 'course_english')) locked,
           exists (select 1 from pipeline.layer4_review_items i where i.entity_type = 'course' and i.entity_id = co.id and i.field_code = 'course_english' and i.status = 'pending') in_review
      from catalogue.courses co
      join pipeline.coverage_course_pages g on g.course_id = co.id
     where co.provider_id = x.provider_id and co.lifecycle_status = 'active' and g.read_status = 'read'
       and coalesce(g.candidates->'adapter_extra'->>'english_level', '') <> ''
  loop
    v_lv := x.proposal->'levels'->r.k;
    if jsonb_typeof(v_lv) is distinct from 'array' or jsonb_array_length(v_lv) = 0 then
      v_unknown := jsonb_set(v_unknown, array[coalesce(r.k, '?')], to_jsonb(coalesce((v_unknown->>coalesce(r.k, '?'))::int, 0) + 1)); continue;
    end if;
    if r.locked or r.in_review then v_held := v_held + 1; continue; end if;
    -- the course page prints its own score for a test of the level, and it differs: the page has its own requirement (an accreditation
    -- standard, for example), so the level is not used for this course and rows this rule wrote before are withdrawn
    if exists (select 1 from jsonb_array_elements(v_lv) q
                join ref.english_tests t on t.code = upper(q->>'test_code')
                join catalogue.course_english_requirements e on e.course_id = r.course_id and e.english_test_id = t.id and e.status = 'active'
               where coalesce(e.source_requirement_key, '') not like 'policy:%' and e.overall_score <> (q->>'overall_score')::numeric) then
      v_own_differs := v_own_differs + 1;
      if p_apply then
        with w as (
          update catalogue.course_english_requirements e set status = 'withdrawn', last_verified_at = now(),
                 notes = coalesce(e.notes, '') || format(' Withdrawn %s: the course page prints its own English score, which differs from level "%s" (Decision 264).', v_day, btrim(r.raw))
           where e.course_id = r.course_id and e.status = 'active' and e.source_requirement_key like 'policy:%' and e.notes like 'English level %Decision 264%'
          returning e.course_id)
        select count(*) into v_out from w;
        v_withdrawn := v_withdrawn + v_out;
        if v_out > 0 then v_courses := v_courses || r.course_id; end if;
      end if;
      continue;
    end if;
    v_label := coalesce(x.proposal->'level_names'->>r.k, btrim(r.raw));
    v_tests := array(select upper(q->>'test_code') from jsonb_array_elements(v_lv) q);
    -- the course's own reading (any key that is not a policy's) is never replaced
    v_own := v_own + (select count(*) from jsonb_array_elements(v_lv) q
                       where exists (select 1 from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id
                                      where e.course_id = r.course_id and t.code = upper(q->>'test_code') and e.status = 'active'
                                        and coalesce(e.source_requirement_key, '') not like 'policy:%'))::int;
    select coalesce(jsonb_agg(jsonb_build_object(
             'test_code', upper(q->>'test_code'), 'overall_score', q->'overall_score', 'component_scores', coalesce(q->'component_scores', '{}'::jsonb),
             'source_requirement_key', 'policy:' || x.id || ':' || lower(q->>'test_code'),
             'notes', format('English level "%s" named on the course page (%s); scores for that level from %s''s English language requirements (%s), approved by a Platform Admin (Decision 264).',
                             v_label, r.page_url, v_name, x.url))), '[]'::jsonb)
      into v_write
      from jsonb_array_elements(v_lv) q
     where upper(q->>'test_code') in (select t.code from ref.english_tests t where t.status = 'active')
       and not exists (select 1 from catalogue.course_english_requirements e join ref.english_tests t on t.id = e.english_test_id
                        where e.course_id = r.course_id and t.code = upper(q->>'test_code') and e.status = 'active'
                          and (coalesce(e.source_requirement_key, '') not like 'policy:%'
                               or (e.source_requirement_key = 'policy:' || x.id || ':' || lower(q->>'test_code')
                                   and e.overall_score = (q->>'overall_score')::numeric
                                   and e.component_scores = coalesce(q->'component_scores', '{}'::jsonb)
                                   and e.notes like 'English level %Decision 264%')));
    if jsonb_array_length(v_write) = 0 then v_same := v_same + 1; continue; end if;
    if not p_apply then v_written := v_written + 1; continue; end if;
    begin
      perform security.coverage_apply_course_v1(r.course_id, v_src, x.evidence_id, x.url, x.content_hash, jsonb_build_object('english_requirements', v_write));
      -- policy rows for tests this level does not give are withdrawn (kept, not deleted)
      with w as (
        update catalogue.course_english_requirements e set status = 'withdrawn', last_verified_at = now(),
               notes = coalesce(e.notes, '') || format(' Withdrawn %s: the course page names English level "%s", which does not give this test (Decision 264).', v_day, v_label)
          from ref.english_tests t
         where t.id = e.english_test_id and e.course_id = r.course_id and e.status = 'active'
           and e.source_requirement_key like 'policy:%' and t.code <> all (v_tests)
        returning 1)
      select count(*) into v_out from w;
      v_withdrawn := v_withdrawn + v_out;
      v_written := v_written + 1; v_courses := v_courses || r.course_id;
    exception when others then v_err := v_err + 1; v_last := left(sqlerrm, 200);
    end;
  end loop;
  if cardinality(v_courses) > 0 then
    insert into search.enrichment_source_gates(projection_code, domain_code, source_id, gate_status, approval_ref, approved_at, created_at, updated_at)
    select 'courses', 'course_english', v_src, 'approved', 'CF-CHG-20260915-247; Decision 227 (English from the provider''s policy, approved by a Platform Admin)', now(), now(), now()
     where not exists (select 1 from search.enrichment_source_gates g where g.projection_code = 'courses' and g.domain_code = 'course_english' and g.source_id = v_src);
    perform search.refresh_course_enrichment_scoped_v1(v_courses, true);
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('policies', 'english_levels', 'english_policy: ' || x.url,
            jsonb_build_object('proposal_id', x.id, 'provider_id', x.provider_id, 'courses', cardinality(v_courses), 'withdrawn_rows', v_withdrawn,
                               'unknown_levels', v_unknown, 'decision', 264), null);
  end if;
  update pipeline.provider_policy_proposals
     set apply_summary = coalesce(apply_summary, '{}'::jsonb) || jsonb_build_object('levels', jsonb_build_object(
           'courses_written', v_written, 'unchanged', v_same, 'own_reading_tests', v_own, 'own_differs', v_own_differs, 'held', v_held, 'withdrawn_rows', v_withdrawn,
           'unknown_levels', v_unknown, 'refused', v_err, 'last_error', v_last, 'checked_at', now(), 'applied', p_apply)), updated_at = now()
   where id = x.id and p_apply;
  return jsonb_build_object('policy', x.id, 'courses_written', v_written, 'unchanged', v_same, 'own_reading_tests', v_own, 'own_differs', v_own_differs, 'own_differs', v_own_differs, 'held', v_held,
                            'withdrawn_rows', v_withdrawn, 'unknown_levels', v_unknown, 'refused', v_err, 'last_error', v_last);
end $function$;

revoke execute on function security.english_level_apply_v1(uuid, boolean) from public, anon, authenticated;

select security.english_level_apply_all_v1(true);

do $post$
begin
  if exists (
    select 1
      from pipeline.coverage_course_pages g
      join catalogue.courses c on c.id = g.course_id
      join pipeline.provider_policy_proposals pp on pp.provider_id = c.provider_id and pp.status = 'approved' and jsonb_typeof(pp.proposal->'levels') = 'object'
      cross join lateral jsonb_array_elements(pp.proposal->'levels'->security.english_level_key(g.candidates->'adapter_extra'->>'english_level')) q
      join ref.english_tests t on t.code = upper(q->>'test_code')
      join catalogue.course_english_requirements o on o.course_id = c.id and o.english_test_id = t.id and o.status = 'active'
     where g.read_status = 'read' and coalesce(o.source_requirement_key, '') not like 'policy:%' and o.overall_score <> (q->>'overall_score')::numeric
       and exists (select 1 from catalogue.course_english_requirements e where e.course_id = c.id and e.status = 'active' and e.notes like 'English level %Decision 264%')) then
    raise exception 'Decision 264 fix post-check: a level row remains beside a differing own score';
  end if;
end $post$;
