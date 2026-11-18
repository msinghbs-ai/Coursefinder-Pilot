-- CF-247 S2 - BOOST (Platform Admin directives Thu 19 Nov 2026 05:40 and 06:55, item 2, s722): after the study-load label-block splitter
-- (s721, Pilot #1337, worker coverage-sweep v1.0.24, deployed by Deploy on merge 44384114108), the study-load pages it can now read are
-- released for one re-read. What was read live (19 Nov 2026 ~07:00 AEDT, SELECT only), study-load items of active courses with no study load
-- and no manual lock, on the course's own latest stored page whose text no other course shares (the claim never reads a shared page):
--   590 rejected and 57 failed by the page check, and 173 verified but refused at promotion (213 of the refusals say "the page states a study
--   load for international students; the answer says not stated", 29 "not what the quoted sentence states for international students") -
--   the Domestic/International blocks of CDU, La Trobe and VIT are among them. 820 items in all; a read costs US$0.00006 on average
--   (about US$0.05 for all), at batch.boost_extract items a minute by job boost-extract (every minute).
-- Released items are claimed again by security.boost_extract_claim_v1, which claims only courses whose study load is still null (no
-- overwrite); each answer goes through the existing page check and promotion (Qwen3 30B is the qualified study-load model). The 35 items
-- released earlier stay as they are: their pages are shared, so they are not read.
-- Data update only; no table, function, job or setting is added (G3 75/48).
-- Numbered 20261119063000: above the live head (20261119053000) and clear of open PRs (061500 #1346, 062000 #1341).
-- Replaces: nothing
-- Retires: nothing

set local lock_timeout = '5s';
set local statement_timeout = '120s';  -- fixed: one data update over about 5,500 items

do $g$
begin
  if (select prosrc from pg_proc where oid = 'security.boost_extract_claim_v1(integer)'::regprocedure) not like '%c.study_load is null%' then
    raise exception 'guard: the study-load claim no longer claims only courses with no study load';
  end if;
end $g$;

with shared as (  -- the claim's own set: page text stored for more than one course (computed once)
  select e.content_hash from pipeline.evidence_artifacts e
   where e.evidence_type = 'provider_course_page_text' and e.storage_path is not null and e.content_hash is not null
   group by e.content_hash having count(distinct e.entity_id) > 1),
i as (
  select x.item_key, x.entity_id, x.evidence_id, x.state,
         (select e.id from pipeline.evidence_artifacts e where e.entity_id = x.entity_id and e.evidence_type = 'provider_course_page_text' and e.storage_path is not null
           order by e.captured_at desc nulls last limit 1) as latest_ev,
         (select s.promotion_state from pipeline.boost_inbound_staging s where s.item_key = x.item_key order by s.loaded_at desc nulls last limit 1) as last_promo
    from pipeline.boost_extract_items x join catalogue.courses c on c.id = x.entity_id
   where x.lane = 'study_load' and x.entity = 'course' and c.study_load is null and c.lifecycle_status = 'active'
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = c.id and l.field in ('study_load', 'study_load_source', 'study_load_evidence_id'))),
r as (
  select i.item_key from i join pipeline.evidence_artifacts a on a.id = i.latest_ev
   where i.latest_ev = i.evidence_id
     and (i.state in ('rejected', 'failed') or (i.state = 'verified' and i.last_promo = 'refused'))
     and not exists (select 1 from shared h where h.content_hash = a.content_hash))
update pipeline.boost_extract_items x
   set state = 'released', note = left('s722 (19 Nov 2026): released for one re-read by worker v1.0.24 after the Domestic/International label split (s721); was ' || x.state || coalesce(': ' || x.note, ''), 500)
  from r where x.item_key = r.item_key;

do $c$
declare v_n int;
begin
  select count(*) into v_n from pipeline.boost_extract_items where lane = 'study_load' and state = 'released' and note like 's722 (19 Nov 2026)%';
  raise notice 's722 released: %', v_n;
  if v_n < 700 or v_n > 900 then raise exception 'post-check: % items released, outside the 820 read live (700 to 900)', v_n; end if;  -- fixed: the live read plus drift
  if exists (select 1 from pipeline.boost_extract_items x join catalogue.courses c on c.id = x.entity_id
              where x.note like 's722 (19 Nov 2026)%' and c.study_load is not null) then
    raise exception 'post-check: a released item belongs to a course that holds a study load';
  end if;
end $c$;
