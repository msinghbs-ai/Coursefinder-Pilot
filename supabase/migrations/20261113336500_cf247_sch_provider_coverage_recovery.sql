-- CF-247 F-SCH: provider coverage recovery from the independent audit (Platform Admin S2-Scholarship directive 13 Nov 2026 14:50 §1, §3, §4,
-- and 14:50 "use Firecrawl to maximise crawling and storing the evidence"; Developer Requirements v2.26 F-SCH.11/.12).
-- Why (live, 13 Nov 2026 04:00 UTC):
--   1. Rebranded domains. 25 providers' scholarship discovery still maps an old website, while the catalogue holds the current one. Three are
--      classified universities: Notre Dame Australia (nd.edu.au, now notredame.edu.au), Victoria University of Wellington (vuw.ac.nz, now
--      wgtn.ac.nz) and Southern Queensland (usq.edu.au, now unisq.edu.au). Notre Dame's six official international award terms PDFs on
--      notredame.edu.au were therefore classed "register page on an unowned host" (6 ownership_conflict cases, 6 Layer 4 interventions), and
--      VUW's map found only six general pages, all refused.
--   2. Canadian universities never searched. 73 of the 95 classified Canadian universities have no candidate page and no discovery row: the
--      evidence-based legitimacy rule (scholarship.legitimacy_checks_on) requires an active catalogue course, and no Canadian course is held,
--      so they were refused as not eligible for scholarship maps and searches, and the refill only selects providers with courses. A classified
--      university with its own official website is a legitimate scholarship source whether or not its courses are loaded yet.
--   3. 109 pending "AI could not decide" reviews are technical (the model's reply failed or the stored page could not be read), not reviewer
--      decisions; they wait for a person with nothing to decide.
--   4. The scholarship Firecrawl share (800 a day) was used by 03:00 UTC with 1,846 refusals, while other shares were under-used (reads 300 of
--      1,200, other 68 of 200). The day's total (4,000) and the monthly plan (85,262 left, 17 days) are unchanged.
-- Change:
--   1. Discovery providers whose website host differs from the catalogue's get the catalogue website, keep the old host as an allowed host
--      (old-domain pages and redirects stay theirs) and are queued for a new map; register entries on the provider's own host are then handed to
--      the page reader by the existing register match.
--   2. security.scholarship_legitimacy_v1 also accepts a classified university (security.scholarship_university) that is active, published,
--      enrols internationally and has an official website not on a directory (Canadian records have no provider type or courses yet); the
--      refill selects classified
--      universities without courses; the classified universities that pass and are not yet in discovery are queued now.
--   3. The technical reviews are superseded (machine, with a note) and their pages are read again fresh (a new official copy through the scraper);
--      the 89 reviews about an unproven audience, value or name stay with people.
--   4. firecrawl.daily_share_scholarships 800 -> 1,500 within the unchanged 4,000 day total; a control event records it.
--   5. Four active scholarships linked to an artefact with no stored copy are linked to the latest stored artefact of the same URL (kept, not deleted).
--   Admission, publication and Layer 4 policy are unchanged; nothing is admitted or published here.
-- Replaces: security.scholarship_legitimacy_v1(uuid), security.scholarship_discovery_refill_v1(integer) (same names and signatures;
--   md5-guarded edits of the live text).
-- Retires: the course-presence requirement for classified universities' scholarship discovery (replaced in place).

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

-- 1. rebranded domains: the catalogue website is the discovery website; the old host stays allowed
with moved as (
  select d.provider_id, d.website old_site, security.url_base_host(d.website) old_host, p.website new_site
    from pipeline.scholarship_discovery_providers d join catalogue.providers p on p.id = d.provider_id
   where nullif(btrim(p.website), '') is not null and not security.third_party_host_v1(p.website)
     and security.url_base_host(d.website) is distinct from security.url_base_host(p.website)
     and not security.url_on_provider_site(p.website, d.website) and not security.url_on_provider_site(d.website, p.website))
update pipeline.scholarship_discovery_providers d
   set website = m.new_site, site_origin = substring(m.new_site from '^(https?://[^/]+)'),
       allowed_hosts = (select array_agg(distinct h) from unnest(coalesce(d.allowed_hosts, '{}') || m.old_host) h where h is not null),
       status = 'pending', attempts = 0, next_discover_at = now(), last_error = null,
       reason = left(coalesce(d.reason, '') || ' | 20261113336500: website moved from ' || coalesce(m.old_site, '?'), 300), updated_at = now()
  from moved m where m.provider_id = d.provider_id;

select public.svc_scholarship_register_match(r.code) from scholarship.registers r where r.role = 'index';

-- 2. classified universities are legitimate scholarship sources without loaded courses
select pg_temp.edit_n('security.scholarship_legitimacy_v1(uuid)', '90bdbf40913bdd120810bd6b7ff3e3bd', array[
  array[$o$                        >= security.pipeline_num_v1('scholarship.legitimacy_min_courses', 1))$o$,
        $n$                        >= security.pipeline_num_v1('scholarship.legitimacy_min_courses', 1))
      -- F-SCH 13 Nov 2026: a classified university with its own official website, without loaded courses or a provider type yet
      or exists (select 1 from catalogue.providers p where p.id = p_provider_id and p.lifecycle_status = 'active' and p.publication_status = 'published'
                    and p.enrols_international is not false and nullif(btrim(coalesce(p.website, '')), '') is not null and not security.third_party_host_v1(p.website)
                    and security.scholarship_university(p.id))$n$]
], array[1]);

select pg_temp.edit_n('security.scholarship_discovery_refill_v1(integer)', 'aa26bbc2b99e3390a4730abc2fa14992', array[
  array[$o$                   count(*) n
              from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
             where co.lifecycle_status = 'active' and k.scholarship_ingestion_enabled$o$,
        $n$                   count(co.id) n
              from catalogue.providers p join ref.countries k on k.id = p.country_id
              left join catalogue.courses co on co.provider_id = p.id and co.lifecycle_status = 'active'
             where k.scholarship_ingestion_enabled and (co.id is not null or security.scholarship_university(p.id))  -- F-SCH 13 Nov 2026: classified universities without courses$n$]
], array[1]);

insert into pipeline.scholarship_discovery_providers(provider_id, website, priority, reason, status)
select p.id, p.website, security.pipeline_num_v1('scholarship.refill_priority_focus', 4)::int, 'university_without_courses (20261113336500)', 'pending'
  from catalogue.providers p
 where security.scholarship_university(p.id) and nullif(btrim(p.website), '') is not null
   and not exists (select 1 from pipeline.scholarship_discovery_providers d where d.provider_id = p.id)
   and security.fc_sch_eligible_v1(p.id) and not security.third_party_host_v1(p.website)
   and not security.provider_sch_search_off_v1(p.id)
   and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p.id)
on conflict do nothing;

-- 3. technical "AI could not decide" reviews: read again fresh; the reviewer questions stay with people
with a as (select * from security.scholarship_ai_active_v1()),
rv as (
  update pipeline.scholarship_ai_reviews r
     set status = 'superseded', decided_at = now(), note = 'Technical failure, read again fresh by the machine (20261113336500, S2-Scholarship 13 Nov 2026 §3)'
   where r.status = 'pending' and (r.reason like 'the model''s reply failed%' or r.reason like 'Approved read: the page could not be read%')
  returning r.*)
insert into pipeline.scholarship_ai_queue(model_code, prompt_version, run_kind, candidate_id, scholarship_id, provider_id, url, fresh_read)
select a.model_code, a.prompt_version, case when rv.scholarship_id is not null then 'reread' else 'admit' end, rv.candidate_id, rv.scholarship_id, rv.provider_id, rv.url, true
  from rv cross join a
 where rv.url is not null
   and not exists (select 1 from pipeline.scholarship_ai_queue q where q.state in ('queued', 'leased')
                    and (q.candidate_id = rv.candidate_id or q.scholarship_id = rv.scholarship_id));

-- 5. evidence chain: an active scholarship whose linked artefact has no stored copy (four, first-party verification of 4 Sep 2026) is linked to
--    the latest stored, hashed artefact of the same official URL; the earlier artefact is kept (nothing deleted) and the change recorded
with nx as (
  select s.id, s.evidence_id old_ev,
         (select e3.id from pipeline.evidence_artifacts e3 where e3.source_url = s.source_url and e3.storage_path is not null and e3.content_hash is not null
           order by e3.captured_at desc limit 1) new_ev
    from scholarship.scholarships s join pipeline.evidence_artifacts e on e.id = s.evidence_id
   where s.lifecycle_status = 'active' and e.storage_path is null),
up as (update scholarship.scholarships s set evidence_id = nx.new_ev, updated_at = now() from nx where nx.id = s.id and nx.new_ev is not null returning s.id, nx.old_ev, nx.new_ev)
insert into pipeline.scholarship_sweep_changes(scholarship_id, field, before_value, after_value, evidence_id)
select up.id, 'evidence_id', to_jsonb(up.old_ev), jsonb_build_object('by', '20261113336500', 'rule', 'latest_stored_artefact_same_url', 'evidence_id', up.new_ev), up.new_ev from up;

-- 4. the scholarship share within the unchanged day total
update pipeline.platform_toolset_settings set value = '1500'::jsonb
 where toolset_key = 'firecrawl' and key = 'daily_share_scholarships' and value = '800'::jsonb;

insert into pipeline.admin_control_events(area, action, target, detail, actor)
values ('scholarships', 'provider_coverage_recovery', 'pipeline.scholarship_discovery_providers',
        jsonb_build_object('migration', '20261113336500', 'directive', 'S2-Scholarship 13 Nov 2026 14:50',
                           'moved_domains', (select count(*) from pipeline.scholarship_discovery_providers where reason like '%20261113336500: website moved%'),
                           'universities_queued', (select count(*) from pipeline.scholarship_discovery_providers where reason = 'university_without_courses (20261113336500)'),
                           'technical_reviews_reread', (select count(*) from pipeline.scholarship_ai_reviews where note like 'Technical failure, read again fresh by the machine (20261113336500%'),
                           'firecrawl_daily_share_scholarships', jsonb_build_object('from', 800, 'to', 1500, 'day_total_unchanged', 4000)), null);
