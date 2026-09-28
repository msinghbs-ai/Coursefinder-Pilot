-- CF-247 / R21 step 1b: keep the scoring text exactly as the page-level index used it
-- (the lexically greatest lower-cased link text seen for the URL), so candidate scores are unchanged.
alter table pipeline.provider_discovery_links add column if not exists score_text text not null default '';
update pipeline.provider_discovery_links d set score_text=x.t
  from (select s.provider_id, l.url, max(lower(coalesce(l.anchor_text,''))) t
          from pipeline.evidence_links l join pipeline.evidence_artifacts e on e.id=l.evidence_id join pipeline.sources s on s.id=e.source_id
         where s.provider_id is not null and l.same_site group by 1,2) x
 where x.provider_id=d.provider_id and x.url=d.url and d.score_text is distinct from x.t;
do $patch$
declare v_def text:=pg_get_functiondef('security.layer2_catalogue_candidates_v2(uuid,integer)'::regprocedure);
begin
  if (select count(*) from regexp_matches(v_def,'lower\(coalesce\(d\.anchor_text,''''\)\) txt','g'))<>1 then raise exception 'v2 scoring anchor not found exactly once'; end if;
  execute replace(v_def,'lower(coalesce(d.anchor_text,'''')) txt','d.score_text txt');
end $patch$;
