-- CF-247 / R26 (approved 28 Sep 2026): new Layer 2 captures reuse an identical stored file.
-- Before: a capture only reused a file when the same page group repeated, so the same page captured
-- for different courses (for example one provider page per course) stored a new identical file each
-- time (about 600 a week in September).
-- Now: for screenshots and HTML snapshots, when an earlier record of the same provider source already
-- holds a stored file with the same SHA-256, the new record is still created (its own capture time,
-- URL, job and metadata: the proof of when the page was seen) but points at that stored file.
-- The capture reply returns the stored path as storage_path and the just-uploaded path as
-- duplicate_upload_path. Callers that already remove duplicate uploads do so straight away; any upload
-- left behind is logged so the evidence-storage-dedupe job removes it once nothing references it.
-- Consumer API: not touched.

do $guard$
begin
  if md5(pg_get_functiondef('public.layer2_evidence_capture(uuid,uuid,text,text,text,text,text,uuid,text,text,timestamptz,jsonb)'::regprocedure))<>'0d018a38f3add394d81eb07492d7f4ce' then
    raise exception 'layer2_evidence_capture changed since review; not replaced'; end if;
end $guard$;

CREATE OR REPLACE FUNCTION public.layer2_evidence_capture(p_source_id uuid, p_job_id uuid, p_evidence_type text, p_source_url text, p_storage_path text, p_content_hash text, p_mime_type text, p_profile_version_id uuid, p_group_key text, p_retention_class text, p_retain_until timestamp with time zone, p_metadata jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'pipeline'
AS $function$ declare prev pipeline.evidence_artifacts%rowtype; v_id uuid; v_cap integer; v_changed boolean; v_now timestamptz:=now(); v_path text:=p_storage_path; v_reused text; v_meta jsonb; begin if current_user not in ('service_role','postgres') then raise exception 'service_role required' using errcode='42501'; end if; select * into prev from pipeline.evidence_artifacts where evidence_group_key=p_group_key order by capture_version desc limit 1 for update; if prev.id is not null and prev.content_hash is not distinct from p_content_hash then return jsonb_build_object('evidence_id',prev.id,'capture_version',prev.capture_version,'content_changed',false,'supersedes_evidence_id',prev.supersedes_evidence_id,'storage_path',prev.storage_path,'duplicate_upload_path',p_storage_path); end if;
 -- R26: reuse an identical stored file of the same provider source (screenshots and HTML snapshots).
 if p_evidence_type in ('layer2_screenshot','layer2_html_snapshot') and p_content_hash ~ '^[0-9a-f]{64}$' and p_source_id is not null then
   select e.storage_path into v_reused from pipeline.evidence_artifacts e
     join storage.objects o on o.bucket_id='evidence' and o.name=e.storage_path
    where e.source_id=p_source_id and e.content_hash=p_content_hash and e.evidence_type=p_evidence_type
      and e.storage_path is not null and e.storage_path<>p_storage_path
    order by e.created_at, e.storage_path limit 1;
   if v_reused is not null then v_path:=v_reused; end if;
 end if;
 v_cap:=coalesce(prev.capture_version,0)+1; v_changed:=true; if prev.id is not null then update pipeline.evidence_artifacts set valid_to=v_now where id=prev.id; end if;
 v_meta:=coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object('content_changed',v_changed);
 if v_reused is not null then v_meta:=v_meta||jsonb_build_object('storage_reused_identical_file',true,'storage_upload_path',p_storage_path); end if;
 insert into pipeline.evidence_artifacts(source_id,job_id,evidence_type,source_url,storage_path,content_hash,mime_type,captured_at,valid_from,supersedes_evidence_id,source_profile_version_id,retention_class,retain_until,review_state,capture_version,evidence_group_key,metadata) values(p_source_id,p_job_id,p_evidence_type,p_source_url,v_path,p_content_hash,p_mime_type,v_now,v_now,prev.id,p_profile_version_id,coalesce(p_retention_class,'standard_365'),p_retain_until,'unreviewed',v_cap,p_group_key,v_meta) returning id into v_id;
 if v_reused is not null then
   insert into pipeline.evidence_storage_dedupe_log(path,keeper_path,content_hash,bytes,source_id,scope,repointed_rows)
   values(p_storage_path,v_reused,p_content_hash,null,p_source_id,'layer2_capture',1) on conflict (path) do nothing;
 end if;
 return jsonb_build_object('evidence_id',v_id,'capture_version',v_cap,'content_changed',v_changed,'supersedes_evidence_id',prev.id,'storage_path',v_path,'duplicate_upload_path',case when v_reused is not null then p_storage_path end,'storage_reused',v_reused is not null); end $function$;

-- Remove left-behind uploads daily (only paths no record references; see svc_evidence_dedupe_next).
select cron.unschedule(jobid) from cron.job where jobname='evidence-storage-dedupe-daily';
select cron.schedule('evidence-storage-dedupe-daily','17 19 * * *',
  $c$select pipeline.svc_pilot_submit_nonce('evidence-storage-dedupe','{"remove":true,"limit":100}'::jsonb)$c$);
