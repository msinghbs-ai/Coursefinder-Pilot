-- CF-247 s1296 (follow-up, same assignment; SS-Programme-Control 27 Nov 2026 11:27 AEDT, S2-AER): the first live tick read 800 courses and 627 of them were
-- skipped at once as "no proven course page (E16)": a course with no page bound to it cannot be read, so offering it again each day wastes
-- the tick's room and repeats an unsuccessful attempt. The selector now holds such a course until a page is bound to it (course-link work).
-- Replaces: the not_a_read eligibility in security.aer_first_read_state_v1 (a technical retry timer alone, for a course with no proven page).
-- Retires: nothing.
-- Consumer API change approved: none; no consumer object is touched.

create temp table s1296b_guard on commit drop as select (select count(*) from pipeline.manual_locks) locks_before, (select count(*) from cron.job) cron_before;

insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by)
values ('pipeline', 'aer.no_page_pattern', 'Entry requirements: outcome that means no page is bound to the course',
  'A course whose last outcome matches this pattern (PostgreSQL regular expression) is not offered for a first read until a page is bound to it. A read cannot succeed without a proven page, so a timer alone would repeat it.',
  'text', to_jsonb('^no proven course page'::text), null, null, 'pattern', 1158,
  'CF-247 s1296: a course with no proven page waits for the page, not a timer', 'Entry requirements', 'security.aer_first_read_state_v1')
on conflict (toolset_key, key) do nothing;

create or replace function security.aer_first_read_state_v1(p_provider uuid default null)
returns table(course_id uuid, provider_id uuid, country text, provider_name text, tier integer, title text, read_class text, eligible boolean, why text, signature text)
language sql stable security definer set search_path = ''
as $f$
  with s as (
    select coalesce(security.toolset_setting('pipeline', 'aer.retry_now_error_pattern') #>> '{}', '') refused,
           coalesce(security.toolset_setting('pipeline', 'aer.not_a_read_pattern') #>> '{}', '') notread,
           coalesce(security.toolset_setting('pipeline', 'aer.no_page_pattern') #>> '{}', '') nopage,
           coalesce(security.toolset_setting('pipeline', 'aer.no_result_pattern') #>> '{}', '') noresult,
           coalesce(security.toolset_setting('pipeline', 'aer.no_result_reader_pattern') #>> '{}', '') noreader,
           coalesce(security.toolset_setting('pipeline', 'aer.page_limit_pattern') #>> '{}', '') pagelimit,
           coalesce(security.toolset_setting('pipeline', 'aer.domestic_statistic_pattern') #>> '{}', '') dom,
           coalesce(security.toolset_setting('pipeline', 'aer.domestic_statistic_exclude') #>> '{}', '') domx,
           coalesce(security.toolset_setting('pipeline', 'aer.ai_after_det_outcomes'), '["no_reading", "no_row"]'::jsonb) detok,
           make_interval(hours => security.pipeline_num_v1('aer.schedule_technical_retry_hours', 24)::int) tech,
           make_interval(days => security.pipeline_num_v1('aer.schedule_retry_days', 30)::int) retry,
           security.pipeline_num_v1('layer4.reader_revision', 1)::text rev,
           (select max(t.updated_at) from pipeline.platform_toolset_settings t
             where t.toolset_key = 'pipeline'
               and exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'aer.read_again_change_keys'), '["layer4.reader_revision"]'::jsonb)) k where t.key like k)) changed_at,
           (select a.extractor from pipeline.aer_det_academic_pages a order by a.read_at desc nulls last limit 1) det_ext),
  c as (select p.* from security.aer_course_population_v1(p_provider) p
         where not exists (select 1 from catalogue.course_entry_requirements x where x.course_id = p.course_id and x.status in ('active', 'proposed'))
           and not exists (select 1 from pipeline.layer4_review_items r where r.entity_id = p.course_id and r.field_code = 'course_entry_first_read' and r.status = 'pending')),
  l as (select c.*, f.state last_state, coalesce(f.reason, '') last_reason, f.updated_at last_at, f.evidence_id last_ev, f.value last_value,
               g.evidence_id bound_ev,
               (select a.outcome from pipeline.aer_det_academic_pages a, s where a.course_id = c.course_id and a.evidence_id = g.evidence_id and a.extractor = s.det_ext
                 order by a.read_at desc nulls last limit 1) det,
               (select x.gate from pipeline.layer4_review_items r join pipeline.layer4_item_readiness x on x.item_id = r.id
                 where r.entity_id = c.course_id and r.field_code = 'course_entry_first_read' and r.status = 'superseded' order by r.decided_at desc nulls last limit 1) gate
          from c
          left join lateral (select * from pipeline.field_enrich_items f where f.course_id = c.course_id and f.field = 'entry_requirements' order by f.updated_at desc, f.id desc limit 1) f on true
          left join lateral (select pg.evidence_id from pipeline.coverage_course_pages pg where pg.course_id = c.course_id and pg.status = 'bound' order by pg.bound_at desc nulls last limit 1) g on true),
  k as (select l.*, s.nopage, s.tech, s.retry, s.changed_at, s.detok, s.rev, s.dom, s.domx,
               case
                 when l.last_state in ('queued', 'waiting', 'ai', 'leased', 'review') then 'in_progress'
                 when l.last_state is null then 'never_read'
                 when s.pagelimit <> '' and l.last_reason ~* s.pagelimit then 'page_limit'
                 when l.last_reason ~* '^held_partial: over_row_limit' then 'row_limit'
                 when s.noresult <> '' and l.last_reason ~* s.noresult then 'read_no_result'
                 when s.noreader <> '' and l.last_reason ~* s.noreader then 'read_no_row'
                 when l.last_reason like 'Layer 4 superseded%' and l.gate is not null and security.aer_e13_class_v1(l.gate) is not null then 'incomplete_read'
                 when (s.notread <> '' and l.last_reason ~* s.notread) or (s.refused <> '' and l.last_reason ~* s.refused) then 'not_a_read'
                 else 'other' end read_class
          from l cross join s),
  d as (select k.*,
               (k.last_ev is distinct from k.bound_ev) copy_changed,
               md5(coalesce(k.bound_ev::text, '-') || ':' || k.rev) sig,
               case when k.read_class = 'incomplete_read' then
                      case when security.aer_e13_class_v1(k.gate) = 'drops_uncovered'
                                and jsonb_array_length(coalesce(k.gate->'drops_uncovered', '[]'::jsonb)) > 0
                                and not exists (select 1 from jsonb_array_elements(k.gate->'drops_uncovered') x
                                                 where not (x->>'reason' = 'quote_not_on_page' and k.dom <> '' and coalesce(x->>'quote', '') ~* k.dom
                                                            and not (k.domx <> '' and coalesce(x->>'quote', '') ~* k.domx)))
                           then 'domestic_only' else 'other_drops' end end drops
          from k)
  select d.course_id, d.provider_id, d.country, d.provider_name, d.tier, d.title, d.read_class,
         ((case
            when d.read_class = 'in_progress' then false
            when d.det is not null and not (d.detok ? d.det) then false  -- reader selection: the deterministic reader's outcome on this copy is not a reading problem
            when d.read_class = 'never_read' then true
            when d.read_class = 'not_a_read' then d.last_at < now() - d.tech and not (d.nopage <> '' and d.last_reason ~* d.nopage and d.bound_ev is null)  -- a course with no proven page cannot be read until one is bound
            when d.read_class = 'incomplete_read' then d.copy_changed or (d.drops = 'domestic_only' and d.last_at < now() - d.tech)
            when d.read_class in ('read_no_result', 'page_limit') then d.copy_changed
            when d.read_class = 'read_no_row' then d.copy_changed or d.changed_at > d.last_at
            when d.read_class = 'row_limit' then d.copy_changed or coalesce(security.course_entry_max_rows_v1(d.provider_id), 0) > coalesce((d.last_value->>'limit')::int, 0)
            else d.last_at < now() - d.retry end)
         and coalesce((security.ops_learning_retry_check_v1('aer_first_read:unchanged_copy_no_result', d.course_id::text, d.sig)->>'allowed')::boolean, true)
         and not (d.det is not null and not (d.detok ? d.det))) as eligible,
         case
           when d.read_class = 'in_progress' then 'a read of this course is in progress'
           when d.det is not null and not (d.detok ? d.det) then 'the deterministic reader''s outcome on this copy is ' || d.det || ': not a reading problem for the AI reader'
           when d.read_class = 'never_read' then 'never read'
           when d.read_class = 'not_a_read' then case when d.nopage <> '' and d.last_reason ~* d.nopage and d.bound_ev is null then 'no proven course page yet: a read waits until a page is bound to this course (course-link work, not a reading problem)' when d.last_at < now() - d.tech then 'the last outcome was not a read: ' || left(d.last_reason, 80) else 'the last outcome was not a read, asked less than the technical retry hours ago' end
           when d.read_class = 'incomplete_read' then case when d.copy_changed then 'the stored copy changed since the incomplete read'
                                                           when d.drops = 'domestic_only' then 'the incomplete read dropped only domestic cut-off statistics, which the reader no longer holds a read for'
                                                           else 'the incomplete read dropped printed requirements that are not domestic statistics (' || coalesce(security.aer_e13_class_v1(d.gate), 'incomplete') || '): the same reader would drop them again; a reader for this structure is needed' end
           when d.read_class in ('read_no_result', 'page_limit') then case when d.copy_changed then 'the stored copy changed since the read' else 'unchanged copy: the same read would give the same result (' || left(d.last_reason, 60) || ')' end
           when d.read_class = 'read_no_row' then case when d.copy_changed then 'the stored copy changed since the read' when d.changed_at > d.last_at then 'the reader changed since the read' else 'unchanged copy and reader: the same read would give the same result (' || left(d.last_reason, 60) || ')' end
           when d.read_class = 'row_limit' then case when d.copy_changed then 'the stored copy changed since the read' when coalesce(security.course_entry_max_rows_v1(d.provider_id), 0) > coalesce((d.last_value->>'limit')::int, 0) then 'the row limit rose' else 'the page has more requirements than the row limit; a limit for this university is the Platform Admin''s to set' end
           else 'read again after the read-again days' end why,
         d.sig signature
    from d
$f$;
comment on function security.aer_first_read_state_v1(uuid) is 'CF-247 s1296: the one rule for the next read of a course with no entry row (class, eligibility, reason, signature). Read only.';

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 or jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) > 0 then raise exception 'post-check: consumer API drift: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select locks_before from s1296b_guard) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job) <> (select cron_before from s1296b_guard) then raise exception 'post-check: a cron job changed'; end if;
  if security.toolset_setting('pipeline', 'aer.no_page_pattern') is null then raise exception 'post-check: the no-page setting is missing'; end if;
end $c$;
