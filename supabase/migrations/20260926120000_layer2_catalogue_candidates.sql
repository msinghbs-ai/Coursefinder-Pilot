-- Package 7 (Decision 146): rank a provider's candidate course catalogue pages from the evidence
-- link index (stored evidence only). Deterministic scoring; each candidate carries the stored
-- capture it was found in, so people and later layers can see the evidence.
create or replace function security.layer2_catalogue_candidates_v1(p_provider_id uuid, p_limit int default 5)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','pipeline','catalogue'
as $$
  with l as (
    select l.url, l.anchor_text, l.evidence_id,
           lower(regexp_replace(l.url,'^https?://[^/]+','')) path, lower(coalesce(l.anchor_text,'')) txt
    from pipeline.evidence_links l
    join pipeline.evidence_artifacts e on e.id=l.evidence_id
    join pipeline.sources s on s.id=e.source_id
    where s.provider_id=p_provider_id and l.same_site),
  agg as (
    select url, (array_agg(anchor_text order by length(coalesce(anchor_text,'')) desc))[1] anchor_text,
           (array_agg(evidence_id))[1] evidence_id, count(distinct evidence_id) pages, max(path) path, max(txt) txt
    from l group by url),
  scored as (
    select a.*,
      (case when (a.path||' '||a.txt) ~ '(find|search|explore|browse|all)[-_ ]?(a[-_ ]|our[-_ ]|for[-_ ]a[-_ ])?(degree|course|program)'
                 or (a.path||' '||a.txt) ~ '(course|degree|program)[-_ ]?(search|finder)' then 60
            when (a.path||' '||a.txt) ~ '(course|degree|program)s?[-_ ]?(list|guide|explorer)' then 45 else 0 end)
     +(case when a.path ~ '/(courses?|degrees?|programs?|programmes?|handbook|study-options)(/|$|\?)' then 30 else 0 end)
     +(case when a.txt ~ '(course|degree|program)' then 15 else 0 end)
     +(case when array_length(regexp_split_to_array(trim(both '/' from split_part(a.path,'?',1)),'/'),1) <= 3 then 5 else 0 end)
     +least(a.pages-1,10)
     -(case when (a.path||' '||a.txt) ~ '(help|apply|fee|accommodation|contact|research|expert|parent|educator|campus|chat|news|event|scholarship|login|portal|alumni|staff|library|career|\.pdf|enquir|visit|open-day|agent)' then 40 else 0 end) score
    from agg a)
  select coalesce(jsonb_agg(jsonb_build_object('url',url,'link_text',anchor_text,'score',score,'found_on_pages',pages,'evidence_id',evidence_id) order by score desc, length(url)),'[]'::jsonb)
  from (select * from scored where score >= 30 order by score desc, length(url) limit greatest(1,least(coalesce(p_limit,5),20))) t
$$;
revoke all on function security.layer2_catalogue_candidates_v1(uuid,int) from public, anon, authenticated;
