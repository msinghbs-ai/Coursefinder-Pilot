begin;

-- Administration -> Sources & Imports is an edition workflow, not a raw revision ledger.
-- Preserve every manual_import revision and its Evidence in ranking.manual_imports, but return
-- only the latest visible revision for each publisher system + edition year. The existing
-- logical_revision_count continues to expose how many retained source revisions exist.
create or replace function security.admin_ranking_imports_read(p_args jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','ranking','pipeline','auth'
as $$
declare
  v_rank integer:=0;
  v_limit integer:=least(greatest(coalesce(nullif(p_args->>'limit','')::integer,50),1),200);
  v_offset integer:=greatest(coalesce(nullif(p_args->>'offset','')::integer,0),0);
  v_include_history boolean:=coalesce((p_args->>'include_history')::boolean,false);
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<4 then raise exception 'pipeline_operator role required' using errcode='42501'; end if;

  return (
    with visible_imports as (
      select mi.*
      from ranking.manual_imports mi
      where v_include_history or mi.status<>'rejected'
    ),
    latest_editions as (
      select distinct on (mi.system_id,mi.edition_year)
        mi.*
      from visible_imports mi
      order by mi.system_id,mi.edition_year,
               mi.updated_at desc nulls last,
               mi.uploaded_at desc nulls last,
               mi.id desc
    )
    select jsonb_build_object(
      'total',(select count(*) from latest_editions),
      'limit',v_limit,
      'offset',v_offset,
      'items',coalesce((
        select jsonb_agg(to_jsonb(x) order by x.updated_at desc nulls last,x.uploaded_at desc nulls last)
        from (
          select mi.id,s.code system_code,mi.edition_year,mi.publisher_name,mi.source_url,mi.methodology_url,
            mi.licensing_note,mi.revision_note,mi.original_filename,mi.mime_type,mi.byte_size,mi.content_hash,
            mi.storage_path,mi.evidence_artifact_id,mi.status,mi.validation_summary,mi.parse_summary,
            mi.uploaded_at,mi.updated_at,
            coalesce((
              select coalesce(j.result->'detected_scope',j.payload->'detected_scope','[]'::jsonb)
              from pipeline.jobs j
              where j.domain='ranking'
                and j.job_type='ranking_import_acquire'
                and j.payload->>'import_id'=mi.id::text
              order by j.created_at desc limit 1
            ),'[]'::jsonb) detected_scope,
            (select count(*)
             from ranking.manual_imports mi2
             where mi2.system_id=mi.system_id
               and mi2.edition_year=mi.edition_year
               and (v_include_history or mi2.status<>'rejected'))::integer logical_revision_count,
            (select jsonb_build_object('id',j.id,'job_type',j.job_type,'status',j.status,'created_at',j.created_at,
               'started_at',j.started_at,'completed_at',j.completed_at,'error_text',j.error_text)
             from pipeline.jobs j
             where j.domain='ranking' and j.payload->>'import_id'=mi.id::text
             order by j.created_at desc limit 1) latest_job,
            (select count(*)
             from pipeline.jobs j
             where j.domain='ranking' and j.payload->>'import_id'=mi.id::text)::integer job_count
          from latest_editions mi
          join ranking.systems s on s.id=mi.system_id
          order by mi.updated_at desc nulls last,mi.uploaded_at desc nulls last,mi.id desc
          limit v_limit offset v_offset
        ) x
      ),'[]'::jsonb)
    )
  );
end
$$;

revoke all on function security.admin_ranking_imports_read(jsonb) from public, anon;
grant execute on function security.admin_ranking_imports_read(jsonb) to authenticated, service_role;

commit;
