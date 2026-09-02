begin;

create or replace function pipeline.sync_layer1_statistical_edition(p_source_id uuid)
returns void language plpgsql security definer
set search_path to 'pg_catalog','pipeline','ref','catalogue'
as $$
declare v pipeline.sources%rowtype; v_family_code text; v_family pipeline.layer1_dataset_families%rowtype;
        v_key text; v_year integer; v_start date; v_end date; v_count bigint; v_prior uuid;
begin
 select * into v from pipeline.sources where id=p_source_id;
 if v.id is null then return; end if;
 if upper(coalesce(v.metadata->>'source_system',v.metadata->>'publisher','')) not in ('QILT','PRISMS') then return; end if;
 v_family_code:=case
   when v.metadata->>'survey_code'='qilt_gos' then 'au_qilt_gos'
   when v.metadata->>'survey_code'='qilt_ses' then 'au_qilt_ses'
   when v.metadata->>'survey_code'='qilt_gosl' then 'au_qilt_gosl'
   when v.metadata->>'survey_code'='qilt_ess' then 'au_qilt_ess'
   when upper(coalesce(v.metadata->>'source_system',''))='PRISMS' then 'au_prisms_student_flow'
 end;
 if v_family_code is null then return; end if;
 select * into v_family from pipeline.layer1_dataset_families where family_code=v_family_code;
 v_key:=coalesce(v.metadata->>'collection_version',v.metadata->>'edition_year',substring(v.label from '(20[0-9]{2}(?:-[0-9]{2})?)'),'unknown');
 v_year:=case when v_key ~ '^20[0-9]{2}' then substring(v_key from 1 for 4)::integer else null end;
 v_start:=nullif(v.metadata->>'period_start','')::date;
 v_end:=nullif(v.metadata->>'period_end','')::date;
 if v_family.source_system='QILT' then select count(*)::bigint into v_count from catalogue.provider_outcomes where source_id=v.id;
 else select count(*)::bigint into v_count from catalogue.student_flow_observations where source_id=v.id; end if;

 insert into pipeline.layer1_dataset_editions(family_id,source_id,edition_key,edition_year,period_start,period_end,status,observation_count,last_verified_at,metadata)
 values(v_family.id,v.id,v_key,v_year,v_start,v_end,'retained',v_count,coalesce(v.last_success_at,v.last_checked_at),
        jsonb_build_object('retained_for_comparison',true,'identity_authority',false))
 on conflict(source_id) do update set edition_key=excluded.edition_key,edition_year=excluded.edition_year,period_start=excluded.period_start,period_end=excluded.period_end,
 observation_count=excluded.observation_count,last_verified_at=excluded.last_verified_at,metadata=pipeline.layer1_dataset_editions.metadata||excluded.metadata;

 select f.current_source_id into v_prior from pipeline.layer1_dataset_families f where f.id=v_family.id;
 if v_prior is null or not exists(
   select 1 from pipeline.layer1_dataset_editions cur join pipeline.layer1_dataset_editions neu on neu.source_id=v.id
   where cur.source_id=v_prior and neu.family_id=cur.family_id
     and coalesce(neu.period_end,make_date(coalesce(neu.edition_year,0),12,31),date '0001-01-01')
         <= coalesce(cur.period_end,make_date(coalesce(cur.edition_year,0),12,31),date '0001-01-01')
 ) then
   update pipeline.layer1_dataset_editions set status='retained' where family_id=v_family.id and source_id<>v.id and status='current';
   update pipeline.layer1_dataset_editions set status='current' where source_id=v.id;
   update pipeline.layer1_dataset_families set current_source_id=v.id,updated_at=now() where id=v_family.id;
   update pipeline.sources set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('edition_status','retained','retain_for_comparison',true) where id=v_prior and v_prior is not null;
   update pipeline.sources set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('dataset_family_code',v_family.family_code,'dataset_family_label',v_family.label,'edition_key',v_key,'edition_year',v_year,'edition_status','current','retain_for_comparison',true) where id=v.id;

   if not exists(select 1 from pipeline.layer1_source_operations where source_id=v.id) then
     insert into pipeline.layer1_source_operations(
       source_id,authority_name,authority_domains,expected_format,expected_count_kind,active,paused,
       verification_cadence_days,ingestion_cadence_days,variance_warn_percent,variance_block_percent,
       previous_accepted_count,last_expected_count,last_verified_at,verification_status,verification_message,
       variance_percent,variance_decision,next_verification_at,next_ingestion_at,change_reason,updated_at
     )
     select v.id,o.authority_name,o.authority_domains,o.expected_format,'observations',true,false,
       o.verification_cadence_days,o.ingestion_cadence_days,o.variance_warn_percent,o.variance_block_percent,
       v_count,v_count,coalesce(v.last_success_at,v.last_checked_at),'passed',
       'New statistical edition registered automatically; retained editions remain available for comparison.',
       0,'pass',now()+(o.verification_cadence_days||' days')::interval,
       now()+(coalesce(o.ingestion_cadence_days,30)||' days')::interval,
       'CF-CHG-20260902-067 automatic statistical edition rollover',now()
     from pipeline.layer1_source_operations o where o.source_id=v_prior
     limit 1;
   end if;

   if v_prior is not null and not exists(select 1 from pipeline.refresh_policies where layer=1 and source_id=v.id) then
     insert into pipeline.refresh_policies(
       country_code,layer,source_profile_id,entity_type,entity_id,freshness_class,cadence_interval,next_due_at,
       hash_sensitive,important_date_sensitive,enabled,change_control_ref,updated_at,source_id
     )
     select country_code,layer,source_profile_id,entity_type,entity_id,freshness_class,cadence_interval,
       now()+cadence_interval,hash_sensitive,important_date_sensitive,enabled,'CF-CHG-20260902-067',now(),v.id
     from pipeline.refresh_policies where layer=1 and source_id=v_prior
     order by updated_at desc limit 1;
     update pipeline.refresh_policies set enabled=false,updated_at=now(),change_control_ref='CF-CHG-20260902-067'
     where layer=1 and source_id=v_prior;
   end if;
 end if;
end $$;

revoke all on function pipeline.sync_layer1_statistical_edition(uuid) from public,anon,authenticated;
grant execute on function pipeline.sync_layer1_statistical_edition(uuid) to service_role;

commit;