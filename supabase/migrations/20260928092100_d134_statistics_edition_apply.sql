-- CF-247 / R6 (Decision 134): applying a checked edition candidate registers it as the family's new current
-- edition. The new source gets the family's operations profile (copied from the previous edition), the previous
-- edition is kept as 'retained' for comparison and stops being verified on schedule, and the family points to the
-- new edition. Also: monthly discovery job, and its one-time nonce.

create or replace function public.svc_statistics_candidate_applied(p_candidate_id bigint, p_actor uuid, p_result jsonb)
returns void language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare c pipeline.statistics_edition_candidates; r pipeline.statistics_edition_rules; f pipeline.layer1_dataset_families;
        v_source uuid; v_old uuid; v_key text; v_year int; v_rows bigint;
begin
  select * into c from pipeline.statistics_edition_candidates where id=p_candidate_id for update;
  if not found then raise exception 'candidate not found'; end if;
  select * into r from pipeline.statistics_edition_rules where member_code=c.member_code for update;
  select * into f from pipeline.layer1_dataset_families where family_code=r.family_code for update;
  v_source:=nullif(p_result->>'sourceId','')::uuid; v_old:=r.current_source_id;
  v_key:=coalesce(nullif(p_result->>'collectionVersion',''), c.edition_year::text);
  v_year:=coalesce(c.edition_year, nullif(left(coalesce(p_result->>'collectionVersion',''),4),'')::int);
  v_rows:=nullif(p_result->>'candidateObservations','')::bigint;
  update pipeline.statistics_edition_candidates set status='applied', applied_at=now(), applied_by=p_actor, applied_source_id=v_source,
         check_result=coalesce(check_result,'{}'::jsonb)||jsonb_build_object('apply',p_result) where id=p_candidate_id;
  if v_source is null or v_source=v_old then return; end if;

  update pipeline.sources s set metadata=coalesce((select o.metadata from pipeline.sources o where o.id=v_old),'{}'::jsonb) || coalesce(s.metadata,'{}'::jsonb)
         || jsonb_build_object('edition_year',v_year,'edition_key',v_key,'edition_status','current','collection_version',v_key), updated_at=now()
   where s.id=v_source;
  update pipeline.sources set metadata=metadata||jsonb_build_object('edition_status','retained'), updated_at=now() where id=v_old;

  insert into pipeline.layer1_source_operations(source_id,authority_name,authority_domains,expected_format,expected_count_kind,active,paused,verification_cadence_days,
         ingestion_cadence_days,variance_warn_percent,variance_block_percent,min_expected_records,max_expected_records,last_expected_count,verification_status,
         verification_message,next_verification_at,change_reason,updated_by,updated_at)
  select v_source,o.authority_name,o.authority_domains,o.expected_format,o.expected_count_kind,true,false,o.verification_cadence_days,
         o.ingestion_cadence_days,o.variance_warn_percent,o.variance_block_percent,null,null,v_rows,'passed',
         'New edition applied from the statistics discovery candidate',now()+make_interval(days=>o.verification_cadence_days),
         'Decision 134 new edition',p_actor,now()
    from pipeline.layer1_source_operations o where o.source_id=v_old
  on conflict (source_id) do nothing;
  update pipeline.layer1_source_operations set next_verification_at=null, change_reason='Retained edition (replaced by a newer edition)', updated_at=now() where source_id=v_old;

  if f.id is not null then
    update pipeline.layer1_dataset_editions set status='retained' where family_id=f.id and status='current';
    insert into pipeline.layer1_dataset_editions(family_id,source_id,edition_key,edition_year,status,observation_count,first_seen_at,last_verified_at,metadata)
    values(f.id,v_source,v_key,v_year,'current',v_rows,now(),now(),jsonb_build_object('candidate_id',p_candidate_id,'file_url',c.file_url))
    on conflict (source_id) do update set status='current', edition_key=excluded.edition_key, observation_count=excluded.observation_count, last_verified_at=now();
    update pipeline.layer1_dataset_families set current_source_id=v_source, updated_at=now() where id=f.id;
  end if;
  update pipeline.statistics_edition_rules set current_source_id=v_source where member_code=r.member_code;
end $f$;
revoke all on function public.svc_statistics_candidate_applied(bigint,uuid,jsonb) from public, anon, authenticated;
grant execute on function public.svc_statistics_candidate_applied(bigint,uuid,jsonb) to service_role;

-- Nonce allow-list: the discovery job (checksum-guarded).
do $patch$
declare v_def text; v_md5 text;
begin
  v_def:=pg_get_functiondef('pipeline.svc_pilot_submit_nonce(text,jsonb)'::regprocedure);
  if v_def like '%''statistics-edition-discovery''%' then return; end if;
  if (select count(*) from regexp_matches(v_def,'''ranking-publisher-control'',','g'))<>1 then raise exception 'allow-list anchor not found exactly once'; end if;
  execute replace(v_def,'''ranking-publisher-control'',','''ranking-publisher-control'',''statistics-edition-discovery'',');
end $patch$;

-- Monthly check for new statistics editions (5th of each month, 02:41 UTC).
select cron.unschedule(jobid) from cron.job where jobname='statistics-edition-discovery';
select cron.schedule('statistics-edition-discovery','41 2 5 * *',
  $c$select pipeline.svc_pilot_submit_nonce('statistics-edition-discovery','{}'::jsonb)$c$);
