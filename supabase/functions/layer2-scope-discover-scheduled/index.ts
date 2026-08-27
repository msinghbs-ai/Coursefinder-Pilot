import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const FN="layer2-scope-discover-scheduled",BUCKET="evidence",VERSION="layer2-scope-discover-scheduled-v1.2.6";
const J=(status:number,body:unknown)=>new Response(JSON.stringify(body),{status,headers:{"content-type":"application/json","cache-control":"no-store"}});
const clean=(v:unknown)=>String(v??"").replace(/\s+/g," ").trim();
const norm=(v:unknown)=>clean(v).toLowerCase().replace(/[^a-z0-9]+/g," ").trim();
const mimeOnly=(v:unknown)=>clean(v||"text/html").split(";")[0].trim().toLowerCase()||"text/html";
const U=(v:unknown)=>{try{return new URL(String(v||""))}catch{return null}};
async function rpc(c:any,n:string,a:any={}){const{data,error}=await c.rpc(n,a);if(error)throw new Error(`${n}: ${error.message}`);return data}
async function digest(bytes:Uint8Array){const d=await crypto.subtle.digest("SHA-256",bytes);return[...new Uint8Array(d)].map(x=>x.toString(16).padStart(2,"0")).join("")}
function similarity(a:string,b:string){const A=new Set(norm(a).split(" ").filter(x=>x.length>2)),B=new Set(norm(b).split(" ").filter(x=>x.length>2));if(!A.size||!B.size)return 0;let n=0;for(const x of A)if(B.has(x))n++;return n/Math.max(A.size,B.size)}
function stripHtml(s:string){return clean(s.replace(/<[^>]+>/g," ").replace(/&amp;/gi,"&").replace(/&quot;/gi,'"').replace(/&#39;/gi,"'").replace(/&nbsp;/gi," "))}
function extractLinks(html:string,base:string){const out:any[]=[],seen=new Set<string>(),re=/<a\b[^>]*href\s*=\s*["']([^"']+)["'][^>]*>([\s\S]*?)<\/a>/gi;let m:RegExpExecArray|null;while((m=re.exec(html))){try{const u=new URL(m[1],base);if(!["http:","https:"].includes(u.protocol))continue;u.hash="";const url=u.toString();if(seen.has(url))continue;seen.add(url);out.push({url,title:stripHtml(m[2])})}catch{}}return out}
function approvedUrl(raw:string,cfg:any){const u=new URL(raw);if(u.protocol!=="https:")throw new Error("https source required");const refs=[cfg.base_domain,cfg.discovery_url,...(cfg.url_patterns||[]),cfg.discovery_strategy?.catalogue_url,cfg.discovery_strategy?.search_url_template].filter(Boolean),hosts=new Set<string>();for(const x of refs){try{hosts.add(new URL(String(x).replace("{query}","x")).hostname.toLowerCase())}catch{}}if(!hosts.has(u.hostname.toLowerCase()))throw new Error(`discovery host not approved: ${u.hostname}`);return u.toString()}
function discoveryUrl(cfg:any,course:any){const d=cfg.discovery_strategy||{};if(d.type==="first_party_search"&&d.search_url_template){const q=encodeURIComponent(clean(`${course.course_code||""} ${course.canonical_title||course.display_title||""}`));return approvedUrl(String(d.search_url_template).replace("{query}",q),cfg)}const url=d.catalogue_url||cfg.discovery_url;if(!url)throw new Error("profile discovery URL missing");return approvedUrl(String(url),cfg)}
function fallbackReason(status:number|null,error:string|null){if(error==="timeout")return"timeout";if(status===403)return"403";if(status===429)return"429";if(status&&status>=500)return"5xx";if(status&&status>=400)return String(status);return error?"blocked":"extraction_failed"}
function canFallback(route:any,reason:string){const allowed=(route?.fallback_on||[]).map((x:any)=>String(x).toLowerCase());return allowed.includes(reason.toLowerCase())||allowed.includes("blocked")&&reason==="network_error"}
async function acquireHtml(svc:any,rt:any,target:string,jobId:string,ua:string,cfg:any){
 const failures:any[]=[],courseStarted=performance.now(),courseBudgetMs=Math.min(Math.max(Number(cfg?.discovery_strategy?.course_acquisition_budget_ms||70000),15000),90000);
 for(const route of (rt.routes||[])){
  const remainingCourseBudget=courseBudgetMs-(performance.now()-courseStarted);
  if(remainingCourseBudget<=5000){failures.push({reason:"course_acquisition_budget_exhausted"});break;}
  const pc=await rpc(svc,"layer2_provider_runtime_config",{p_provider_id:route.provider_id});
  if(!pc?.enabled){failures.push({provider_id:route.provider_id,reason:"provider_disabled"});continue}
  if(pc.auth_scheme!=="none"&&!pc.secret){failures.push({provider_key:pc.provider_key,reason:"credential_missing"});continue}
  if(pc.budget_status?.allowed===false){failures.push({provider_key:pc.provider_key,reason:"budget_blocked"});continue}
  if(pc.provider_key!=="direct-http"&&pc.estimated_request_cost_usd==null){failures.push({provider_key:pc.provider_key,reason:"cost_unknown"});continue}
  const attemptId=await rpc(svc,"layer2_provider_attempt_start",{p_job_id:jobId,p_provider_id:pc.id,p_request_url:target});
  const st=performance.now();let fetchUrl=target,method="GET",body:any=undefined,headers:any={"user-agent":ua||"CourseFinder Layer2 Discovery/1.1","accept":"text/html,application/xhtml+xml,application/json"};
  try{
   if(pc.adapter_type!=="direct_http"){
    const base=U(pc.base_url);if(!base)throw new Error("provider_base_url_invalid");
    const t=pc.request_template||{},o=route.request_overrides||{};method=String(o.method||t.method||"GET").toUpperCase();
    if(method.startsWith("POST")){
      const field=String(o.target_url_field||t.target_url_field||"url");body=JSON.stringify({...t.static_body,...o.static_body,[field]:target});headers["content-type"]="application/json";method="POST";fetchUrl=base.toString();
    }else{
      base.searchParams.set(String(o.target_url_parameter||t.target_url_parameter||"url"),target);
      for(const[k,v]of Object.entries(t.static_query||{}))base.searchParams.set(k,String(v));
      for(const[k,v]of Object.entries(o.static_query||{}))base.searchParams.set(k,String(v));
      fetchUrl=base.toString();
    }
    if(pc.auth_scheme==="query_param"){const z=new URL(fetchUrl);z.searchParams.set(pc.auth_field_name||"token",pc.secret);fetchUrl=z.toString()}
    else if(pc.auth_scheme==="bearer")headers.authorization="Bearer "+pc.secret;
    else if(pc.auth_scheme==="header")headers[pc.auth_field_name||"X-Api-Key"]=pc.secret;
   }
   const providerTimeoutMs=Math.min(Math.max(Number(pc.timeout_seconds||30),5),120)*1000,fetchBudgetMs=Math.max(5000,Math.min(providerTimeoutMs,courseBudgetMs-(performance.now()-courseStarted))),ctl=new AbortController(),timer=setTimeout(()=>ctl.abort(),fetchBudgetMs);let res:Response;
   try{res=await fetch(fetchUrl,{method,body,headers,redirect:"follow",signal:ctl.signal})}finally{clearTimeout(timer)}
   const raw=await res.text(),latency=Math.round(performance.now()-st);
   if(!res.ok){
     const reason=fallbackReason(res.status,null);
     await rpc(svc,"layer2_provider_attempt_finish",{p_attempt_id:attemptId,p_status:"failed",p_http_status:res.status,p_mime:mimeOnly(res.headers.get("content-type")),p_raw_evidence:null,p_html_evidence:null,p_screenshot_evidence:null,p_extraction_status:"not_attempted",p_blocker:`HTTP ${res.status}`,p_metrics:{operation:"scope_discovery",provider_key:pc.provider_key,route_priority:route.priority,fallback_reason:reason,latency_ms:latency,worker_version:VERSION}});
     failures.push({provider_key:pc.provider_key,http_status:res.status,reason});
     if(canFallback(route,reason))continue;
     throw new Error(`route_stopped:${pc.provider_key}:${reason}`);
   }
   let html=raw;
   if(String(pc.request_template?.response_adapter||"").toLowerCase()==="firecrawl_v2"){
     let parsed:any;try{parsed=JSON.parse(raw)}catch{throw new Error("firecrawl_invalid_json")}
     html=String(parsed?.data?.html||parsed?.html||"");
   }
   if(!html||!/<[a-z][\s\S]*>/i.test(html)){
     const reason="extraction_failed";
     await rpc(svc,"layer2_provider_attempt_finish",{p_attempt_id:attemptId,p_status:"extraction_failed",p_http_status:res.status,p_mime:mimeOnly(res.headers.get("content-type")),p_raw_evidence:null,p_html_evidence:null,p_screenshot_evidence:null,p_extraction_status:"discovery_html_missing",p_blocker:"provider response did not contain usable HTML",p_metrics:{operation:"scope_discovery",provider_key:pc.provider_key,route_priority:route.priority,fallback_reason:reason,latency_ms:latency,worker_version:VERSION}});
     failures.push({provider_key:pc.provider_key,reason});
     if(canFallback(route,reason))continue;
     throw new Error(`route_stopped:${pc.provider_key}:${reason}`);
   }
   const requiredPrefix=clean(cfg?.discovery_strategy?.require_url_prefix);
   if(requiredPrefix){
     const matchingLinks=extractLinks(html,target).filter((x:any)=>{try{return new URL(x.url).pathname.toLowerCase().startsWith(requiredPrefix.toLowerCase())}catch{return false}});
     if(!matchingLinks.length){
       const reason="extraction_failed";
       await rpc(svc,"layer2_provider_attempt_finish",{p_attempt_id:attemptId,p_status:"extraction_failed",p_http_status:res.status,p_mime:"text/html",p_raw_evidence:null,p_html_evidence:null,p_screenshot_evidence:null,p_extraction_status:"discovery_required_link_missing",p_blocker:`no discovery link matched required prefix ${requiredPrefix}`,p_metrics:{operation:"scope_discovery",provider_key:pc.provider_key,route_priority:route.priority,fallback_reason:reason,latency_ms:latency,worker_version:VERSION,required_url_prefix:requiredPrefix}});
       failures.push({provider_key:pc.provider_key,reason,required_url_prefix:requiredPrefix});
       if(canFallback(route,reason))continue;
       throw new Error(`route_stopped:${pc.provider_key}:${reason}`);
     }
   }
   return{attemptId,providerId:pc.id,providerKey:pc.provider_key,httpStatus:res.status,mime:"text/html",html,sourceUrl:target,latency,routePriority:route.priority,failures};
  }catch(e:any){
   const isAbort=e?.name==="AbortError",msg=isAbort?"timeout":String(e.message||e);
   if(!msg.startsWith("route_stopped:")){
     const reason=isAbort?"timeout":"blocked";
     try{await rpc(svc,"layer2_provider_attempt_finish",{p_attempt_id:attemptId,p_status:isAbort?"failed":"blocked",p_http_status:null,p_mime:null,p_raw_evidence:null,p_html_evidence:null,p_screenshot_evidence:null,p_extraction_status:"not_attempted",p_blocker:msg.slice(0,1000),p_metrics:{operation:"scope_discovery",provider_key:pc.provider_key,route_priority:route.priority,fallback_reason:reason,worker_version:VERSION}})}catch{}
     failures.push({provider_key:pc.provider_key,reason});
     if(canFallback(route,reason)&&(performance.now()-courseStarted)<courseBudgetMs-5000)continue;
   }
   throw e;
  }
 }
 throw new Error("providers_exhausted:"+JSON.stringify(failures));
}
function rankCandidates(course:any,html:string,base:string,cfg:any){const expectedTitle=clean(course.canonical_title||course.display_title),expectedCode=clean(course.course_code).toUpperCase(),esc=expectedCode.replace(/[.*+?^${}()|[\]\\]/g,"\\$&"),requiredPrefix=clean(cfg?.discovery_strategy?.require_url_prefix).toLowerCase(),links=extractLinks(html,base).filter((x:any)=>{if(!requiredPrefix)return true;try{return new URL(x.url).pathname.toLowerCase().startsWith(requiredPrefix)}catch{return false}}),candidates=links.map((x:any)=>{const observedTitle=clean(x.title||""),nExpected=norm(expectedTitle),nObserved=norm(observedTitle),titleScore=(nExpected&&nObserved&&(nObserved===nExpected||(nObserved.startsWith(nExpected+" ")&&nObserved.split(" ").length-nExpected.split(" ").length<=2)))?1:similarity(expectedTitle,observedTitle),codeInTitle=Boolean(expectedCode)&&new RegExp(`\\b${esc}\\b`,"i").test(x.title||""),codeInUrl=Boolean(expectedCode)&&x.url.toUpperCase().includes(expectedCode),matchScore=Math.min(1,titleScore+(codeInTitle?.35:0)+(codeInUrl?.25:0));return{...x,title_score:Number(titleScore.toFixed(3)),regulatory_code_seen:Boolean(codeInTitle||codeInUrl),match_score:Number(matchScore.toFixed(3))}}).filter((x:any)=>x.match_score>=.35).sort((a:any,b:any)=>b.match_score-a.match_score).slice(0,20);let status="current_page_not_found",blocker:string|null="no plausible current first-party Course page found";if(candidates.length){const top=candidates[0],second=candidates[1];if(top.regulatory_code_seen&&top.match_score>=.8)status="exact_match";else if(top.match_score>=.75&&(!second||top.match_score-second.match_score>=.12))status="likely_match";else if(top.match_score>=.55)status="ambiguous";else status="identity_mismatch";blocker=status==="ambiguous"?"multiple plausible current Course pages":status==="identity_mismatch"?"current page candidate does not sufficiently match selected Course identity":null}return{expectedTitle,expectedCode,candidates,status,blocker,selected:["exact_match","likely_match"].includes(status)}}
Deno.serve(async(req:Request)=>{if(req.method!=="POST")return J(405,{ok:false,error:"POST required",workerVersion:VERSION});const sb=Deno.env.get("SUPABASE_URL")!,sk=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,svc=createClient(sb,sk,{auth:{persistSession:false}});try{
 const nonce=clean(req.headers.get("x-cf-run-nonce"));if(!nonce)throw new Error("one-time schedule nonce required");if(!await rpc(svc,"svc_pilot_consume_nonce",{p_function:FN,p_nonce:nonce}))throw new Error("invalid, expired or already-used schedule nonce");
 const body=await req.json().catch(()=>({})),profileId=clean(body.profile_id),limit=Math.min(Math.max(Number(body.limit||50),1),50),courseIds=Array.isArray(body.course_ids)?body.course_ids.map((x:any)=>clean(x)).filter(Boolean).slice(0,1000):[],chunkIds=courseIds.slice(0,limit),autoSyncActor=clean(body.auto_sync_actor),syncCourseIds=Array.isArray(body.sync_course_ids)?body.sync_course_ids.map((x:any)=>clean(x)).filter(Boolean).slice(0,1000):courseIds;if(!profileId)throw new Error("profile_id required");
 const ctx=courseIds.length?await rpc(svc,"layer2_discovery_context_scope",{p_profile_id:profileId,p_course_ids:chunkIds,p_limit:limit}):await rpc(svc,"layer2_discovery_context",{p_profile_id:profileId,p_limit:limit}),rt=ctx.runtime,cfg=rt.configuration||{},courses=ctx.courses||[],actor=await rpc(svc,"layer2_automation_actor"),job=await rpc(svc,"layer2_prepare_job",{p_actor:actor,p_profile_id:profileId,p_job_type:"layer2_discovery"}),jobId=job.job_id;
 await rpc(svc,"layer2_runtime_job_mark",{p_job_id:jobId,p_status:"running",p_payload:{layer:2,profile_id:profileId,operation:"scope_discovery",routing:"ordered_profile_routes"},p_result:{},p_error:null,p_attempt_count:0});
 const results:any[]=[],invocationStarted=performance.now(),invocationBudgetMs=85000;
 for(const course of courses){let acquired:any=null;try{
   const target=discoveryUrl(cfg,course);acquired=await acquireHtml(svc,rt,target,jobId,cfg.headers?.user_agent,cfg);
   const bytes=new TextEncoder().encode(acquired.html),rawHash=await digest(bytes),rawPath=`layer2/v2/discovery/${profileId}/${jobId}/${course.id}/source.html`,up=await svc.storage.from(BUCKET).upload(rawPath,bytes,{contentType:"text/html",upsert:false});if(up.error)throw new Error(`evidence upload: ${up.error.message}`);
   const raw=await rpc(svc,"layer2_evidence_capture",{p_source_id:rt.source_id,p_job_id:jobId,p_evidence_type:"layer2_html_snapshot",p_source_url:target,p_storage_path:rawPath,p_content_hash:rawHash,p_mime_type:"text/html",p_profile_version_id:rt.version_id,p_group_key:await digest(new TextEncoder().encode(`${rt.version_id}|${course.id}|discovery|${rawHash}`)),p_retention_class:"standard_365",p_retain_until:null,p_metadata:{layer:2,operation:"course_url_discovery",worker_version:VERSION,course_id:course.id,provider_key:acquired.providerKey,route_priority:acquired.routePriority,canonical_mutation_authorised:false}});
   const normalized={layer:2,runtime_version:VERSION,attempt_id:acquired.attemptId,job_id:jobId,provider_key:acquired.providerKey,source_evidence_id:raw.evidence_id,source_url:target,html:acquired.html,text:acquired.html,structured:null,canonical_mutation_authorised:false},normBytes=new TextEncoder().encode(JSON.stringify(normalized)),normHash=await digest(normBytes),normPath=`layer2/v2/discovery/${profileId}/${jobId}/${course.id}/extraction-input.json`,nu=await svc.storage.from(BUCKET).upload(normPath,normBytes,{contentType:"application/json",upsert:false});if(nu.error)throw new Error(`normalized upload: ${nu.error.message}`);
   const nev=await rpc(svc,"layer2_evidence_capture",{p_source_id:rt.source_id,p_job_id:jobId,p_evidence_type:"layer2_extraction_input",p_source_url:target,p_storage_path:normPath,p_content_hash:normHash,p_mime_type:"application/json",p_profile_version_id:rt.version_id,p_group_key:await digest(new TextEncoder().encode(`${raw.evidence_id}|scope-discovery`)),p_retention_class:"standard_365",p_retain_until:null,p_metadata:{layer:2,operation:"course_url_discovery",worker_version:VERSION,course_id:course.id,source_evidence_id:raw.evidence_id,attempt_id:acquired.attemptId,provider_key:acquired.providerKey,canonical_mutation_authorised:false}});
   const ranked=rankCandidates(course,acquired.html,target,cfg),rows:any[]=[];
   if(ranked.candidates.length)ranked.candidates.forEach((x:any,i:number)=>rows.push({course_id:course.id,source_profile_version_id:rt.version_id,provider_attempt_id:acquired.attemptId,evidence_id:nev.evidence_id,discovered_url:x.url,discovered_title:x.title,discovered_regulatory_code:x.regulatory_code_seen?ranked.expectedCode:null,match_score:x.match_score,match_basis:{title_score:x.title_score,regulatory_code_seen:x.regulatory_code_seen,expected_title:ranked.expectedTitle,expected_course_code:ranked.expectedCode,worker_version:VERSION,provider_key:acquired.providerKey},status:i===0?ranked.status:"candidate",selected:i===0&&ranked.selected,blocker:i===0?ranked.blocker:null}));
   else rows.push({course_id:course.id,source_profile_version_id:rt.version_id,provider_attempt_id:acquired.attemptId,evidence_id:nev.evidence_id,status:"current_page_not_found",selected:false,match_basis:{expected_title:ranked.expectedTitle,expected_course_code:ranked.expectedCode,worker_version:VERSION,provider_key:acquired.providerKey},blocker:ranked.blocker});
   const written=await rpc(svc,"layer2_discovery_candidates_write",{p_rows:rows});if(Number(written)!==rows.length)throw new Error(`candidate write count mismatch: ${written}/${rows.length}`);
   await rpc(svc,"layer2_provider_attempt_finish",{p_attempt_id:acquired.attemptId,p_status:"succeeded",p_http_status:acquired.httpStatus,p_mime:"text/html",p_raw_evidence:raw.evidence_id,p_html_evidence:raw.evidence_id,p_screenshot_evidence:null,p_extraction_status:"discovery_evaluated",p_blocker:ranked.blocker,p_metrics:{operation:"scope_discovery",candidate_count:ranked.candidates.length,selected:ranked.selected,provider_key:acquired.providerKey,route_priority:acquired.routePriority,prior_failures:acquired.failures,latency_ms:acquired.latency,worker_version:VERSION}});
   results.push({course_id:course.id,status:ranked.status,provider_key:acquired.providerKey,selected_url:ranked.selected?ranked.candidates[0]?.url:null,candidates:ranked.candidates.length});
 }catch(e:any){if(acquired?.attemptId)try{await rpc(svc,"layer2_provider_attempt_finish",{p_attempt_id:acquired.attemptId,p_status:"failed",p_http_status:null,p_mime:null,p_raw_evidence:null,p_html_evidence:null,p_screenshot_evidence:null,p_extraction_status:"blocked",p_blocker:String(e.message||e).slice(0,1000),p_metrics:{operation:"scope_discovery",worker_version:VERSION}})}catch{}results.push({course_id:course.id,status:"failed",error:String(e.message||e)})}
   if((performance.now()-invocationStarted)>=invocationBudgetMs)break;
 }
 const selected=results.filter(x=>x.selected_url).length,failed=results.filter(x=>x.status==="failed").length,finalStatus=results.length>0&&failed===results.length?"failed":"completed";
 await rpc(svc,"layer2_runtime_job_mark",{p_job_id:jobId,p_status:finalStatus,p_payload:{layer:2,profile_id:profileId,operation:"scope_discovery",routing:"ordered_profile_routes"},p_result:{processed:results.length,selected,failed,results},p_error:finalStatus==="failed"?"all discovery items failed":null,p_attempt_count:results.length});
 let continuation_request_id=null,auto_sync_result=null;const actionableSet=new Set(courses.map((x:any)=>clean(x.id))),processedSet=new Set(results.map((x:any)=>clean(x.course_id))),consumedSet=new Set<string>();for(const id of chunkIds){if(!actionableSet.has(id)||processedSet.has(id))consumedSet.add(id)}for(const id of processedSet)consumedSet.add(id);const remaining=courseIds.filter((id:any)=>!consumedSet.has(clean(id)));if(remaining.length){const next=await rpc(svc,"layer2_discovery_scope_dispatch_v2",{p_profile_id:profileId,p_course_ids:remaining,p_limit:limit,p_actor:autoSyncActor||null,p_sync_course_ids:syncCourseIds});continuation_request_id=next?.request_id||null}else if(autoSyncActor&&syncCourseIds.length){auto_sync_result=await rpc(svc,"layer2_scope_profile_batch_service",{p_actor:autoSyncActor,p_profile_id:profileId,p_course_ids:syncCourseIds})}return J(200,{ok:true,workerVersion:VERSION,profile_id:profileId,job_id:jobId,processed:results.length,selected,failed,remaining:remaining.length,continuation_request_id,auto_sync_result,results});
}catch(e:any){return J(500,{ok:false,error:String(e.message||e),workerVersion:VERSION})}});
