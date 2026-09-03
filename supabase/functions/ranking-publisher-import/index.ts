import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const WORKER_ORIGIN = "https://coursefinder-pilot.techm.workers.dev";
const LOCAL_ORIGINS = new Set(["http://localhost:5173","http://127.0.0.1:5173"]);
const MAX_BYTES = 50 * 1024 * 1024;
const ALLOWED = new Map<string,Set<string>>([
  [".csv",new Set(["text/csv","text/plain","application/vnd.ms-excel"])],
  [".xlsx",new Set(["application/vnd.openxmlformats-officedocument.spreadsheetml.sheet","application/octet-stream"])],
  [".pdf",new Set(["application/pdf"])],
  [".json",new Set(["application/json","text/plain"])],
  [".txt",new Set(["text/plain","application/json","application/octet-stream"])],
  [".zip",new Set(["application/zip","application/x-zip-compressed","application/octet-stream"])],
]);

function cors(req:Request){
  const origin=req.headers.get("origin")||"";
  const allow=origin===WORKER_ORIGIN||LOCAL_ORIGINS.has(origin)?origin:WORKER_ORIGIN;
  return {"access-control-allow-origin":allow,"access-control-allow-headers":"authorization, x-client-info, apikey, content-type","access-control-allow-methods":"POST, OPTIONS","cache-control":"no-store","referrer-policy":"no-referrer","vary":"origin"};
}
function reply(req:Request,status:number,body:unknown){return new Response(JSON.stringify(body),{status,headers:{...cors(req),"content-type":"application/json; charset=utf-8"}});}
function txt(v:FormDataEntryValue|null){return String(v??"").trim()}
function safeFileName(v:string){return v.replace(/[^a-zA-Z0-9._-]+/g,"-").replace(/^-+|-+$/g,"").slice(0,120)||"publisher-file"}
function validHttpUrl(v:string){try{const u=new URL(v);return u.protocol==="https:"||u.protocol==="http:"}catch{return false}}
async function sha256Hex(bytes:ArrayBuffer){const hash=await crypto.subtle.digest("SHA-256",bytes);return [...new Uint8Array(hash)].map(b=>b.toString(16).padStart(2,"0")).join("")}

Deno.serve(async(req:Request)=>{
  if(req.method==="OPTIONS") return new Response(null,{status:204,headers:cors(req)});
  if(req.method!=="POST") return reply(req,405,{error:"method_not_allowed"});
  const authHeader=req.headers.get("authorization")||"";
  if(!authHeader.toLowerCase().startsWith("bearer ")) return reply(req,401,{error:"authentication_required"});

  const url=Deno.env.get("SUPABASE_URL");
  const anon=Deno.env.get("SUPABASE_ANON_KEY");
  const service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!anon||!service) return reply(req,500,{error:"service_configuration_error"});

  const userClient=createClient(url,anon,{global:{headers:{Authorization:authHeader}},auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
  const {data:context,error:contextError}=await userClient.rpc("admin_read",{p_operation:"context",p_args:{}});
  if(contextError||!context?.authenticated) return reply(req,401,{error:"authentication_required"});
  if(Number(context?.role_rank||0)<4) return reply(req,403,{error:"pipeline_operator_role_required"});
  const actor=String(context?.user_id||"");
  if(!/^[0-9a-f-]{36}$/i.test(actor)) return reply(req,403,{error:"operator_context_invalid"});

  let form:FormData;
  try{form=await req.formData()}catch{return reply(req,400,{error:"multipart_form_required"})}

  let systemCode=txt(form.get("system_code")).toLowerCase();
  let editionYear=Number(txt(form.get("edition_year")));
  let publisherName=txt(form.get("publisher_name"));
  let sourceUrl=txt(form.get("source_url"));
  const methodologyUrl=txt(form.get("methodology_url"));
  const licensingNote=txt(form.get("licensing_note"));
  const revisionNote=txt(form.get("revision_note"));
  const file=form.get("file");

  if(!(file instanceof File)) return reply(req,400,{error:"publisher_file_required"});
  if(file.size<=0||file.size>MAX_BYTES) return reply(req,400,{error:"file_size_out_of_range",max_bytes:MAX_BYTES});

  const lower=file.name.toLowerCase();
  const ext=[...ALLOWED.keys()].find(x=>lower.endsWith(x));
  if(!ext) return reply(req,400,{error:"unsupported_file_extension",allowed_extensions:[...ALLOWED.keys()]});
  const allowedMimes=ALLOWED.get(ext)!;
  const mime=(file.type||"application/octet-stream").toLowerCase();
  if(!allowedMimes.has(mime)) return reply(req,400,{error:"mime_extension_mismatch",mime_type:mime,extension:ext});

  const bytes=await file.arrayBuffer();
  let detectedNativeThe=false,detectedYear:number|null=null;
  if(ext===".json"||ext===".txt"){
    try{
      let text=new TextDecoder().decode(bytes).replace(/^\uFEFF/,"").trim();
      const hm=text.match(/^Year\s+(\d{4})\s*[\r\n]+/i);
      if(hm){detectedYear=Number(hm[1]);text=text.slice(hm[0].length);}
      const parsed=JSON.parse(text);
      detectedNativeThe=String(parsed?.status||"").toLowerCase()==="success"&&Array.isArray(parsed?.data?.data);
      if(detectedNativeThe){
        systemCode="the_wur";
        if(detectedYear!==null)editionYear=detectedYear;
        publisherName="Times Higher Education";
        sourceUrl="https://www.timeshighereducation.com/world-university-rankings/latest/world-ranking";
      }
    }catch(error){
      if(ext===".txt"||systemCode==="the_wur")return reply(req,400,{error:"the_native_json_invalid",detail:error instanceof Error?error.message:String(error)});
    }
  }

  if(!["qs_wur","the_wur","arwu"].includes(systemCode)) return reply(req,400,{error:"unsupported_ranking_system"});
  if(!Number.isInteger(editionYear)||editionYear<2000||editionYear>2100) return reply(req,400,{error:"valid_edition_year_required"});
  if(!publisherName) return reply(req,400,{error:"publisher_name_required"});
  if(!validHttpUrl(sourceUrl)) return reply(req,400,{error:"valid_source_url_required"});
  if(methodologyUrl&&!validHttpUrl(methodologyUrl)) return reply(req,400,{error:"valid_methodology_url_required"});
  if(licensingNote.length<5) return reply(req,400,{error:"licensing_access_note_required"});

  if((ext===".json"||ext===".txt")&&systemCode==="the_wur"&&!detectedNativeThe)return reply(req,400,{error:"the_native_json_shape_invalid"});
  if(ext===".txt"&&!detectedNativeThe)return reply(req,400,{error:"txt_native_json_is_the_only"});
  const hash=await sha256Hex(bytes);
  const nonce=crypto.randomUUID();
  const path="ranking/"+systemCode+"/"+editionYear+"/"+hash.slice(0,16)+"-"+nonce+"-"+safeFileName(file.name);

  const serviceClient=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}});
  const upload=await serviceClient.storage.from("evidence").upload(path,new Uint8Array(bytes),{contentType:mime,upsert:false,cacheControl:"0"});
  if(upload.error) return reply(req,500,{error:"evidence_upload_failed",detail:upload.error.message});

  try{
    const {data,error}=await serviceClient.rpc("svc_ranking_manual_import_register",{
      p_system_code:systemCode,p_edition_year:editionYear,p_publisher_name:publisherName,p_source_url:sourceUrl,
      p_methodology_url:methodologyUrl||null,p_licensing_note:licensingNote,p_revision_note:revisionNote||null,
      p_original_filename:file.name,p_mime_type:mime,p_byte_size:file.size,p_content_hash:hash,p_storage_path:path,p_uploaded_by:actor
    });
    if(error) throw new Error(error.message||"import_registration_failed");
    if(data?.duplicate){await serviceClient.storage.from("evidence").remove([path]);return reply(req,200,{ok:true,duplicate:true,import_id:data.import_id,content_hash:hash});}
    return reply(req,201,{ok:true,duplicate:false,...data,content_hash:hash,original_filename:file.name,byte_size:file.size});
  }catch(error){
    await serviceClient.storage.from("evidence").remove([path]);
    return reply(req,500,{error:"import_registration_failed",detail:error instanceof Error?error.message:String(error)});
  }
});