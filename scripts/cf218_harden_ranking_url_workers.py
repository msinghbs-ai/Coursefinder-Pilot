from pathlib import Path
import re


def replace_one(text: str, pattern: str, replacement: str, label: str) -> str:
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"{label}: expected one replacement, found {count}")
    return updated


def patch_qs(path: str) -> None:
    p = Path(path)
    s = p.read_text()

    s = replace_one(
        s,
        r'async function registerRaw\(svc:any,year:number,src:string,mode:string,nid:string\|null,bytes:Uint8Array,metadata:any\)\{.*?\}\nDeno\.serve',
        '''async function registerRaw(svc:any,year:number,src:string,mode:string,nid:string|null,bytes:Uint8Array,metadata:any){const hash=await sha(bytes),path=`ranking/qs_wur/${year}/raw-${hash.slice(0,20)}.json`,up=await svc.storage.from("evidence").upload(path,bytes,{contentType:"application/json",upsert:false,cacheControl:"0"});if(up.error&&!/already exists|duplicate/i.test(up.error.message))throw new Error(`raw_evidence_upload_failed: ${up.error.message}`);const{data:ev,error:er}=await svc.rpc("svc_ranking_raw_evidence_register",{p_system_code:"qs_wur",p_edition_year:year,p_source_url:src,p_storage_path:path,p_content_hash:hash,p_mime_type:"application/json",p_metadata:{acquisition_mode:mode,qs_release_nid:nid,...metadata}});if(er)throw new Error(`raw_evidence_register_failed: ${er.message}`);return{id:ev,path,hash}}\nDeno.serve''',
        "QS raw Evidence RPC",
    )

    old_job = 'ji=await svc.schema("pipeline").from("jobs").insert({job_type:"ranking_import_acquire",domain:"ranking",status:"running",requested_by:actor,started_at:new Date().toISOString(),payload:{action:"acquire_generate_validate",acquisition_mode:"qs_url",system_code:"qs_wur",edition_year:year,source_url:src,apply_requested:apply}}).select("id").single(),jobId=ji.data?.id||null'
    new_job = 'ji=await svc.rpc("svc_ranking_job_start",{p_job_type:"ranking_import_acquire",p_source_id:null,p_requested_by:actor,p_payload:{action:"acquire_generate_validate",acquisition_mode:"qs_url",system_code:"qs_wur",edition_year:year,source_url:src,apply_requested:apply}}),jobId=ji.data||null'
    if old_job not in s:
        raise SystemExit("QS job start: source contract changed")
    s = s.replace(old_job, new_job, 1)

    s = replace_one(
        s,
        r'if\(jobId\)await svc\.schema\("pipeline"\)\.from\("jobs"\)\.update\(\{status:"completed",completed_at:new Date\(\)\.toISOString\(\),result:(\{.*?latency_ms:Date\.now\(\)-started\})\}\)\.eq\("id",jobId\)',
        r'if(jobId)await svc.rpc("svc_ranking_job_finish",{p_job_id:jobId,p_status:"completed",p_result:\1,p_error_text:null})',
        "QS job completion RPC",
    )
    s = replace_one(
        s,
        r'if\(jobId\)await svc\.schema\("pipeline"\)\.from\("jobs"\)\.update\(\{status:"failed",completed_at:new Date\(\)\.toISOString\(\),error_text:message,result:(\{ok:false,error:message,latency_ms:Date\.now\(\)-started\})\}\)\.eq\("id",jobId\)',
        r'if(jobId)await svc.rpc("svc_ranking_job_finish",{p_job_id:jobId,p_status:"failed",p_result:\1,p_error_text:message})',
        "QS job failure RPC",
    )

    if '.schema("pipeline").from("jobs")' in s or '.schema("pipeline").from("evidence_artifacts")' in s:
        raise SystemExit("QS private pipeline Data API access remains")
    p.write_text(s)


def patch_the(path: str) -> None:
    p = Path(path)
    s = p.read_text()

    s = replace_one(
        s,
        r'async function rawEvidence\(svc:any,year:number,src:string,raw:any,meta:any\)\{.*?\}\nDeno\.serve',
        '''async function rawEvidence(svc:any,year:number,src:string,raw:any,meta:any){const bytes=new TextEncoder().encode(JSON.stringify({source:"timeshighereducation_public_via_parsebot",source_url:src,edition_year:year,captured_at:new Date().toISOString(),publisher_page:meta,parsebot_scraper:PARSEBOT,payload:raw})),hash=await sha(bytes),path=`ranking/the_wur/${year}/raw-${hash.slice(0,20)}.json`;const up=await svc.storage.from("evidence").upload(path,bytes,{contentType:"application/json",upsert:false,cacheControl:"0"});if(up.error&&!/exists|duplicate/i.test(up.error.message))throw new Error(`raw_evidence_upload_failed: ${up.error.message}`);const{data:ev,error:er}=await svc.rpc("svc_ranking_raw_evidence_register",{p_system_code:"the_wur",p_edition_year:year,p_source_url:src,p_storage_path:path,p_content_hash:hash,p_mime_type:"application/json",p_metadata:{acquisition_mode:"parsebot_the_public_wrapper",publisher_page_total:meta?.total,change_control_ref:"CF-214"}});if(er)throw new Error(`raw_evidence_register_failed: ${er.message}`);return{path,hash,id:ev}}\nDeno.serve''',
        "THE raw Evidence RPC",
    )

    old_job = 'ji=await svc.schema("pipeline").from("jobs").insert({job_type:"ranking_import_acquire",domain:"ranking",status:"running",requested_by:actor,started_at:new Date().toISOString(),payload:{action:"acquire_generate_validate",acquisition_mode:"the_url",system_code:"the_wur",edition_year:year,source_url:src,apply_requested:apply}}).select("id").single(),jobId=ji.data?.id||null'
    new_job = 'ji=await svc.rpc("svc_ranking_job_start",{p_job_type:"ranking_import_acquire",p_source_id:null,p_requested_by:actor,p_payload:{action:"acquire_generate_validate",acquisition_mode:"the_url",system_code:"the_wur",edition_year:year,source_url:src,apply_requested:apply}}),jobId=ji.data||null'
    if old_job not in s:
        raise SystemExit("THE job start: source contract changed")
    s = s.replace(old_job, new_job, 1)

    s = replace_one(
        s,
        r'if\(jobId\)await svc\.schema\("pipeline"\)\.from\("jobs"\)\.update\(\{status:"completed",completed_at:new Date\(\)\.toISOString\(\),result:(\{.*?latency_ms:Date\.now\(\)-started\})\}\)\.eq\("id",jobId\)',
        r'if(jobId)await svc.rpc("svc_ranking_job_finish",{p_job_id:jobId,p_status:"completed",p_result:\1,p_error_text:null})',
        "THE job completion RPC",
    )
    s = replace_one(
        s,
        r'if\(jobId\)await svc\.schema\("pipeline"\)\.from\("jobs"\)\.update\(\{status:"failed",completed_at:new Date\(\)\.toISOString\(\),error_text:message,result:(\{ok:false,error:message\})\}\)\.eq\("id",jobId\)',
        r'if(jobId)await svc.rpc("svc_ranking_job_finish",{p_job_id:jobId,p_status:"failed",p_result:\1,p_error_text:message})',
        "THE job failure RPC",
    )

    if '.schema("pipeline").from("jobs")' in s or '.schema("pipeline").from("evidence_artifacts")' in s:
        raise SystemExit("THE private pipeline Data API access remains")
    p.write_text(s)


patch_qs('supabase/functions/ranking-qs-url-import/index.ts')
patch_the('supabase/functions/ranking-the-url-import/index.ts')
