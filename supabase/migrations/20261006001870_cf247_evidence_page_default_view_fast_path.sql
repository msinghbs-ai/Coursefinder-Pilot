do $p$
declare v_def text; v_new text; v_a text; v_b text;
begin
  select pg_get_functiondef(p.oid) into v_def from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='security' and p.proname='admin_evidence_page' and p.pronargs=1;
  if v_def is null then raise exception 'security.admin_evidence_page not found'; end if;
  if (select md5(p.prosrc) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='security' and p.proname='admin_evidence_page' and p.pronargs=1) <> '9f9c653d52525119c59f9143724366c5' then raise exception 'live admin_evidence_page differs from the assumed definition'; end if;
  v_new := v_def;

  v_a := $a$  v_result jsonb;
begin$a$;
  v_b := $b$  v_result jsonb;
  v_fast boolean;
begin$b$;
  if (length(v_new)-length(replace(v_new,v_a,'')))<>length(v_a) then raise exception 'declare anchor not unique'; end if;
  v_new := replace(v_new,v_a,v_b);

  v_a := $a$  with conflicts as materialized ($a$;
  v_b := $b$  -- Default view (no filters, newest first): only the rows that can appear on the requested page are classified.
  v_fast:=v_query is null and v_country is null and v_source_id is null and v_layer is null and v_entity_type is null and v_entity_id is null and v_provider_id is null and v_job_id is null and v_evidence_type is null and v_mime is null and v_hash is null and v_job_status is null and v_status is null and v_extraction_state is null and v_freshness is null and v_verified_from is null and v_verified_to is null and v_conflicts is null and v_sort='captured' and v_direction='desc';

  with conflicts as materialized ($b$;
  if (length(v_new)-length(replace(v_new,v_a,'')))<>length(v_a) then raise exception 'with anchor not unique'; end if;
  v_new := replace(v_new,v_a,v_b);

  v_a := $a$    where
      (v_query is null or e.id::text ilike$a$;
  v_b := $b$    where
      (not v_fast or e.id in (select c.id from pipeline.evidence_artifacts c order by c.captured_at desc nulls last,c.id limit v_limit+v_offset)) and
      (v_query is null or e.id::text ilike$b$;
  if (length(v_new)-length(replace(v_new,v_a,'')))<>length(v_a) then raise exception 'where anchor not unique'; end if;
  v_new := replace(v_new,v_a,v_b);

  v_a := $a$'total',(select count(*) from filtered)$a$;
  v_b := $b$'total',case when v_fast then (select count(*) from pipeline.evidence_artifacts) else (select count(*) from filtered) end$b$;
  if (length(v_new)-length(replace(v_new,v_a,'')))<>length(v_a) then raise exception 'total anchor not unique'; end if;
  v_new := replace(v_new,v_a,v_b);

  if v_new = v_def then raise exception 'no change made'; end if;
  execute v_new;
end $p$