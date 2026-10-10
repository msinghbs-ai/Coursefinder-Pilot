-- CF-247 / R21 (option A, step 1): keep discovery links once per provider, not once per page.
-- The same navigation links appear on every page of a provider site: 447,678 page-level rows
-- hold only 25,579 distinct provider links. This step creates the per-provider table, backfills it
-- from the page-level index and adds a candidate function that reads it, for side-by-side proof.
-- Nothing is switched over here. Consumer API: not touched.

create table if not exists pipeline.provider_discovery_links(
  provider_id uuid not null references catalogue.providers(id) on delete cascade,
  url text not null,
  anchor_text text,
  pages integer not null default 1,
  evidence_id uuid references pipeline.evidence_artifacts(id) on delete set null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (provider_id, url));
alter table pipeline.provider_discovery_links enable row level security;
revoke all on pipeline.provider_discovery_links from public, anon, authenticated;

insert into pipeline.provider_discovery_links(provider_id,url,anchor_text,pages,evidence_id,first_seen_at,last_seen_at)
select s.provider_id, l.url,
       (array_agg(l.anchor_text order by length(coalesce(l.anchor_text,'')) desc))[1],
       count(distinct l.evidence_id),
       (array_agg(l.evidence_id order by e.captured_at nulls last))[1],
       now(), now()
  from pipeline.evidence_links l
  join pipeline.evidence_artifacts e on e.id=l.evidence_id
  join pipeline.sources s on s.id=e.source_id
 where s.provider_id is not null and l.same_site
 group by s.provider_id, l.url
on conflict (provider_id,url) do nothing;

-- Same scoring as layer2_catalogue_candidates_v1, reading the per-provider table.
create or replace function security.layer2_catalogue_candidates_v2(p_provider_id uuid, p_limit integer default 5)
returns jsonb language sql stable security definer set search_path to 'pg_catalog','pipeline','catalogue' as $function$
  with agg as (
    select d.url, d.anchor_text, d.evidence_id, d.pages,
           lower(regexp_replace(d.url,'^https?://[^/]+','')) path, lower(coalesce(d.anchor_text,'')) txt
    from pipeline.provider_discovery_links d where d.provider_id=p_provider_id),
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
$function$;
revoke all on function security.layer2_catalogue_candidates_v2(uuid,integer) from public, anon, authenticated;
