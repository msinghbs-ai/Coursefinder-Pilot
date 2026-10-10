-- CF-247 (3 Oct 2026, 08:25 AEST). Platform Admin, 08:17: "What's stopping us increasing uni per run. Increase it to 200
-- or more." Nothing technical did: preparing 20 universities takes 0.4 s; the only limit was a cap of 20 written into
-- security.coverage_ai_match_prepare_v1, and the job asked for 4. Found at 08:10: 6,650 courses with no page (5,622 of
-- them Australian) had never been given to the AI link matcher because of that throttle.
-- 1. The cap becomes 500 and the job prepares 200 universities (up to 1,000 courses each) every 2 minutes. md5 guard.
-- 2. The matcher job takes 80 items a minute at 12 at a time (the worker's own ceilings); no worker change.
-- 3. A university whose website is mapped but has no course-page search recipe gets the generic one (any page on its
--    own site; the page rule still decides), as Decisions 220 and 222 do for sites found by search or entered by hand.
--    460 such universities hold courses with no page. No searches are queued here: Firecrawl has 21,788 of 100,000
--    credits left for October (search used 50,480), so the matcher (site map + a cheap pinned model, no Firecrawl)
--    goes first; search is for what the matcher cannot settle.
do $p$
declare s text; d text;
  o1 text := $o$limit greatest(1, least(p_providers, 20))$o$;
  n1 text := $n$limit greatest(1, least(p_providers, 500))$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'security' and p.proname = 'coverage_ai_match_prepare_v1';
  if md5(s) is distinct from '722d5e9c022fd8c466874bf235e6d0e3' then raise exception 'coverage_ai_match_prepare_v1 changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'cap not found once'; end if;
  execute replace(d, o1, n1);
end $p$;

select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-ai-match-prepare'), command := 'select security.coverage_ai_match_prepare_v1(200, 1000)');
select cron.alter_job(job_id := (select jobid from cron.job where jobname = 'coverage-ai-match'), command := $$select pipeline.svc_pilot_submit_nonce('coverage-sweep','{"mode":"ai_match","limit":80,"concurrency":12}'::jsonb)$$);

insert into pipeline.course_link_recipes(provider_id, search_domain, patterns, active, notes, updated_at)
select d.provider_id, v.dom,
       jsonb_build_array(jsonb_build_object(
         're', '(?i)^https?://([a-z0-9-]+\.)*' || regexp_replace(v.dom, '\.', '\\.', 'g')
               || '/(?!.*\.(pdf|docx?|xlsx?|pptx?|jpe?g|png|gif|svg|zip)$)(?!(.*/)?(news|events?|blog|staff|people|media|search|tags?|category)(/|$)).+$',
         'rep', '\&')),
       true, 'Generic recipe: any page on the provider''s own mapped site; used only when the reader proves the page is the course''s (3 Oct 2026, matcher throughput)', now()
  from pipeline.coverage_provider_discovery d
  cross join lateral (select lower(regexp_replace(substring(btrim(d.website) from '^(?:https?://)?([^/:?#]+)'), '^www\.', '')) dom) v
 where d.status = 'mapped' and nullif(d.website, '') is not null and v.dom ~ '^[a-z0-9.-]+\.[a-z]{2,}$'
   and not exists (select 1 from pipeline.course_link_recipes r where r.provider_id = d.provider_id)
   and exists (select 1 from catalogue.courses co where co.provider_id = d.provider_id and co.lifecycle_status = 'active'
               and not exists (select 1 from catalogue.course_links l where l.course_id = co.id and l.link_type = 'official_course'));

select security.coverage_ai_match_prepare_v1(200, 1000);
