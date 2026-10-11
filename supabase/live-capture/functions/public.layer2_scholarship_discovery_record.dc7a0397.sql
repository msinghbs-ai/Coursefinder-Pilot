CREATE OR REPLACE FUNCTION public.layer2_scholarship_discovery_record(p_evidence_id uuid, p_urls jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline'
AS $function$
declare e pipeline.evidence_artifacts%rowtype;x jsonb;n integer:=0;v_url text;v_title text;
begin
 if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if;
 select * into e from pipeline.evidence_artifacts where id=p_evidence_id;if not found then raise exception 'evidence not found';end if;
 for x in select * from jsonb_array_elements(coalesce(p_urls,'[]'::jsonb)) loop
  v_url:=nullif(x->>'url','');v_title:=nullif(x->>'title','');if v_url is null then continue;end if;
  insert into pipeline.layer2_scholarship_discovery_candidates(source_id,evidence_id,source_profile_version_id,scholarship_url,observed_title)
  values(e.source_id,e.id,e.source_profile_version_id,v_url,v_title) on conflict(evidence_id,scholarship_url) do nothing;
  if found then n:=n+1;end if;
 end loop;return n;
end $function$
