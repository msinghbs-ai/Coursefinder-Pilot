-- CF-247 AER shared pages: a binding the identity check REJECTED is not a claim on the page (Platform Admin directive 8 Nov 2026: "resolve ... the 45 shared-page cases through source
-- and identity validation"; development agent, branch cf247-aer-qut-shared). Nothing is read, fetched, spent, approved, admitted, re-bound or deleted.
-- Guards: E13 shared-page hold (entry.shared_page_hold), G2 (the two lists are settings), G3 (no consumer API object, table or column is touched), Decision 260 (housekeeping),
--   "No blanket approvals, nothing auto-admitted; human Layer 4 decisions remain mandatory", "a passing qualification never switches anything on by itself".
-- Replaces: security.course_entry_shared_page_v1 (same name and signature; md5-guarded edit)
-- Retires: nothing
--
-- Live evidence (project fxcwkweaxjtknorudmwp, read only, 8 Nov 2026). 44 waiting course reads are in the shared_page class (the 45 of 7 Nov, minus one that has since moved).
-- security.course_entry_shared_page_v1(course) lists every OTHER course whose pipeline.coverage_course_pages row has the same url, whatever that row's status. A row with status
-- 'mismatch' is the record that the identity check (cricos_code, nzqa_code, exact_title, title_level, ...) refused the page for that course: the url is kept as provenance, the page is
-- not that course's page. Counting it as "also the page of another programme" holds a read for a claim nobody makes. Measured on the 44 (classified in
-- docs/paste/AER-20261108-shared-page-44-classification.md):
--   * 19 reads have a binding that the identity check accepted on a strong basis (cricos_code 16, nzqa_code 3), no hand lock, and every other
--     differently named course on the page is a refused (mismatch) binding. This course's own page. 14 of the 19 carry no other reason and become reviewable; 5 carry a second
--     reason (dropped requirements) and move to that class, which the stored-read recovery already handles.
--   * 25 stay held, unchanged: 11 share the page with another BOUND or AMBIGUOUS course (RMIT BH012 Science (Honours) multi-major page 7, Software Engineering (Professional),
--     Advanced Diploma of Engineering Technology, Photography (Honours), and AMPA 1), and 14 have a hand lock on the course page address (the locked courses stay held unless individually authorised;
--     9 of those 14 also have a binding the identity check refused).
-- What this changes (one function, two settings; behaviour with the settings at their defaults is the new rule, an empty list restores the old rule exactly):
--   security.course_entry_shared_page_v1(course): another course's row counts when its status is in entry.shared_page_count_statuses (default bound, ambiguous). The relaxation applies
--   only to a course whose OWN binding is bound on a basis in entry.shared_page_own_bases (default cricos_code, nzqa_code, adapter_code, exact_title, title_level; a hand binding
--   (manual), a weaker basis, a refused or ambiguous binding keeps the old rule) and which has no hand lock on its page address (pipeline.manual_locks official_url / course_url).
--   Anything else is counted exactly as before. Setting entry.shared_page_own_bases to [] switches the relaxation off.
-- Not changed: the gate, the route, the Layer 4 decision paths, the replay, every other setting. The released reads still go to a person: an item that was held for this reason alone
--   becomes 'complete' and waits for a Platform Admin decision (Approve all, Approve except, Reject); nothing is approved here.
-- Before -> after (live, 8 Nov 2026):
--   security.course_entry_shared_page_v1(uuid) cc037bb72a83595406b1246570d1e977 -> 7b43d0c61419ec08ea2fbb2889b1f444 (measured on the scratch copy of the live definition; the live run prints the same value in its notice)

do $g$
begin
  if to_regprocedure('security.course_entry_shared_page_v1(uuid)') is null or to_regclass('pipeline.coverage_course_pages') is null or to_regclass('pipeline.manual_locks') is null then
    raise exception 'needs E13 / D-R2 (security.course_entry_shared_page_v1), pipeline.coverage_course_pages and pipeline.manual_locks';
  end if;
end $g$;

-- 1 settings (G2) -----------------------------------------------------------------------------------------------------------------------------
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'entry.shared_page_count_statuses', 'Entry requirements: bindings that make a page shared',
  'Another course counts as sharing a stored page when its binding to that page has one of these statuses. bound and ambiguous: a page the identity check accepted, or could not settle, for another programme. Add mismatch to count refused bindings too (the old rule).',
  'list', '["bound", "ambiguous"]'::jsonb, null, null, 'binding statuses', 1470, 'Entry requirements', 'security.course_entry_shared_page_v1',
  'CF-247 AER shared pages (directive 8 Nov 2026): a refused binding is not a claim on the page'),
 ('pipeline', 'entry.shared_page_own_bases', 'Entry requirements: identity bases that let a course ignore refused bindings on its page',
  'A course whose own binding is bound on one of these identity bases, and which has no hand lock on its page address, does not count refused bindings of other courses as sharing its page. Empty: nobody (the old rule).',
  'list', '["cricos_code", "nzqa_code", "adapter_code", "exact_title", "title_level"]'::jsonb, null, null, 'identity bases', 1471, 'Entry requirements', 'security.course_entry_shared_page_v1',
  'CF-247 AER shared pages (directive 8 Nov 2026): only a strongly identified, unlocked course is relaxed')
on conflict (toolset_key, key) do nothing;

-- 2 the edit, md5-guarded ----------------------------------------------------------------------------------------------------------------------
do $edit$
declare v_sig constant text := 'security.course_entry_shared_page_v1(uuid)'; v_before constant text := 'cc037bb72a83595406b1246570d1e977';
        v_def text := pg_get_functiondef('security.course_entry_shared_page_v1(uuid)'::regprocedure); v_old text; v_new text; v_c int;
begin
  if v_def like '%entry.shared_page_count_statuses%' then raise notice '%: already applied', v_sig; return; end if;
  if md5(v_def) <> v_before then raise exception '% differs from the definition this change edits (md5 %)', v_sig, md5(v_def); end if;
  v_old := $o$     and not (coalesce(security.toolset_setting('pipeline', 'entry.variant_check_off_providers'), '[]'::jsonb) ? c1.provider_id::text)$o$;
  v_new := v_old || $n$
     -- CF-247 (8 Nov 2026): a binding the identity check refused (status mismatch) is not a claim on the page. The relaxation is for a course whose own binding the identity check
     -- accepted on a strong basis and which has no hand lock; every other course keeps the old rule (all statuses count).
     and (g2.status = any (array(select jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.shared_page_count_statuses'), '["bound", "ambiguous"]'::jsonb))))
          or g1.status is distinct from 'bound'
          or not (coalesce(security.toolset_setting('pipeline', 'entry.shared_page_own_bases'), '[]'::jsonb) ? coalesce(g1.identity_basis, ''))
          or exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = g1.course_id and l.field in ('official_url', 'course_url')))$n$;
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', v_sig, v_c; end if;
  execute replace(v_def, v_old, v_new);
  raise notice '%: applied, md5 now %', v_sig, md5(pg_get_functiondef('security.course_entry_shared_page_v1(uuid)'::regprocedure));
end $edit$;

comment on function security.course_entry_shared_page_v1(uuid) is 'CF-247 E13 (factored out by D-R2; 8 Nov 2026 edit): the differently named programmes whose stored page is also this course''s page (entry.shared_page_hold). A binding the identity check refused (mismatch) does not count for a course that is itself bound on a strong identity basis and has no hand lock (entry.shared_page_count_statuses, entry.shared_page_own_bases).';

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'entry_requirements', 'shared_page_rule', 'security.course_entry_shared_page_v1',
       jsonb_build_object('change', 'a refused (mismatch) binding no longer makes a page shared for a strongly identified, unlocked course',
                          'settings', jsonb_build_array('entry.shared_page_count_statuses', 'entry.shared_page_own_bases'), 'before_md5', 'cc037bb72a83595406b1246570d1e977',
                          'admits_nothing', true, 'migration', '20261108030000'), null
 where not exists (select 1 from pipeline.admin_control_events e where e.area = 'entry_requirements' and e.action = 'shared_page_rule' and e.detail->>'migration' = '20261108030000');
