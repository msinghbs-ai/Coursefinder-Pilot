-- CF-247 (Decision 220, 2 Oct 2026). Platform Admin, 12:02: "Fan out the data admission of all countries ... Recent
-- managed runs and recent fetches seems to be carried on by old script and make no sense. Should we remove it ...
-- Layer2 overview shows action required but not actionable button or guidance." By multiple choice: retire the old
-- Layer 2 pipeline (pause, keep history); Canada "like New Zealand" (site found by name and checked, programme code or
-- exact title for links, English and intakes, tuition in CAD only from a page that prints the course's code).
--  1. The old Layer 2 reading pipeline is paused: its 7 scheduled jobs are switched off, nothing is removed. Its last
--     fan-out task was created on 13 Sep 2026; the course-page sweep has replaced it. Housekeeping, the onboarding
--     snapshot (read by the evidence link index), the Layer 3 tuition enqueue and the scholarship scope job keep running.
--  2. The site finder returns each provider's country and IRCC DLI number. A Canadian site found by name is recorded
--     with how it was checked; it gets the generic course-page recipe for its own .ca domain and its active courses are
--     queued for the course-page search by title (Canadian course codes are internal identifiers, not official codes).
--  3. Canada's admission rule: exact title for links, English and intakes; tuition only from a page that prints the
--     course's code; currency CAD. The tuition admit and the Layer 4 fee correction accept CAD.
--  4. Every Canadian provider with active courses joins the course-page discovery queue as "no website".
-- Every function patch is behind an md5 guard on its current source.

do $p$
declare r record; s text; d text; i int;
begin
  for r in select * from (values
    ('public','svc_coverage_site_next','54a7df47d41b52982e07dc3728ee63ef',
      array[$o$lower(pr.registration_scheme)='cricos'))$o$],
      array[$n$lower(pr.registration_scheme)='cricos'),'country',security.coverage_country(u.provider_id),
           'dli',(select min(upper(pr.registration_code)) from catalogue.provider_registrations pr where pr.provider_id=u.provider_id and lower(pr.registration_scheme)='ircc_dli'))$n$]),
    ('public','svc_coverage_site_record','5787f94f16616e872c5a655d0903842d',
      array[$o$begin
  if current_user<>'postgres'$o$,
            $o$then 'search_verified_cricos_code' else site_source end$o$,
            $o$   where provider_id=p_provider_id;
end$o$],
      array[$n$declare v_dom text;
begin
  if current_user<>'postgres'$n$,
            $n$then coalesce('search_verified_'||nullif(p_evidence->>'basis',''),'search_verified_cricos_code') else site_source end$n$,
            $n$   where provider_id=p_provider_id;
  -- Decision 220: a Canadian site gets the generic recipe for its own .ca domain, and its active courses with no
  -- candidate page are queued for the course-page search by title.
  if nullif(p_website,'') is not null and security.coverage_country(p_provider_id) = 'CA' then
    v_dom := lower(regexp_replace(substring(btrim(p_website) from '^(?:https?://)?([^/:?#]+)'), '^www\.', ''));
    if v_dom ~ '^[a-z0-9.-]+\.ca$' then
      insert into pipeline.course_link_recipes(provider_id, search_domain, patterns, active, notes, updated_at)
      select p_provider_id, v_dom,
             jsonb_build_array(jsonb_build_object(
               're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(v_dom, '\.', '\\.', 'g')
                     || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
               'rep', '\&')),
             true, 'Generic recipe: any page on the provider''s own site; used only when the reader proves the page is the course''s (CA, Decision 220, 2 Oct 2026)', now()
       where not exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id);
      insert into pipeline.course_link_search(course_id, provider_id, stage, state, queued_at)
      select c.id, c.provider_id, 'title', 'queued', now()
        from catalogue.courses c
       where c.provider_id = p_provider_id and c.lifecycle_status = 'active'
         and exists (select 1 from pipeline.course_link_recipes x where x.provider_id = p_provider_id and x.active)
         and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id)
      on conflict (course_id) do nothing;
    end if;
  end if;
end$n$]),
    ('security','layer3_tuition_admit_assumed_annual_v1','bce0fe0723c56957570ebc84172838ea',
      array[$o$v_cur not in ('AUD','NZD')$o$],
      array[$n$v_cur not in ('AUD','NZD','CAD')$n$]),
    ('security','layer4_tuition_apply_impl','9ed068348c5f34bf1805470607b548a0',
      array[$o$if v_cur not in ('AUD','NZD') then raise exception 'currency must be AUD or NZD'; end if;$o$],
      array[$n$if v_cur not in ('AUD','NZD','CAD') then raise exception 'currency must be AUD, NZD or CAD'; end if;$n$])
  ) t(sch, fn, guard, olds, news) loop
    select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = r.sch and p.proname = r.fn;
    if md5(s) is distinct from r.guard then raise exception '%.% changed (md5 %); not replacing', r.sch, r.fn, md5(s); end if;
    for i in 1..array_length(r.olds, 1) loop
      if (length(d) - length(replace(d, r.olds[i], ''))) / length(r.olds[i]) <> 1 then raise exception '%.% piece % not found once', r.sch, r.fn, i; end if;
      d := replace(d, r.olds[i], r.news[i]);
    end loop;
    execute d;
  end loop;
end $p$;

-- 1. pause the old Layer 2 reading pipeline (switched off, not removed)
select cron.alter_job(j.jobid, active := false)
  from cron.job j
 where j.jobname in ('coursefinder-layer2-fanout-scheduler','coursefinder-layer2-refresh-dispatcher',
                     'coursefinder-layer2-qualification-scheduler','coursefinder-layer2-wave-scheduler',
                     'layer2-auto-discovery','coursefinder-layer2-qualification-finalizer','layer2-stale-wave-closer')
   and j.active;

-- 3. Canada's admission rule
insert into pipeline.coverage_admission_countries(country_id, active, currency_code, identities, approved_ref, updated_at)
select k.id, true, 'CAD',
       jsonb_build_object(
         'official_url', '["exact_title"]'::jsonb,
         'english',      '["exact_title"]'::jsonb,
         'intakes',      '["exact_title"]'::jsonb,
         'tuition',      '["cricos_code"]'::jsonb),
       'Decision 220 (Canada like New Zealand: site found by name and checked against its DLI number or own .ca domain; exact title for links, English and intakes; tuition in CAD only from a page that prints the course''s code; Platform Admin 2 Oct 2026)',
       now()
  from ref.countries k
 where k.iso_alpha2 = 'CA'
on conflict (country_id) do nothing;

-- 4. Canadian providers with active courses join the discovery queue (no website yet; the site finder looks them up)
insert into pipeline.coverage_provider_discovery(provider_id, website, status, attempts, updated_at)
select p.id, nullif(btrim(p.website), ''), case when nullif(btrim(p.website), '') is null then 'no_website' else 'pending' end, 0, now()
  from catalogue.providers p join ref.countries k on k.id = p.country_id
 where k.iso_alpha2 = 'CA'
   and exists (select 1 from catalogue.courses c where c.provider_id = p.id and c.lifecycle_status = 'active')
   and not exists (select 1 from pipeline.coverage_provider_discovery d where d.provider_id = p.id);
