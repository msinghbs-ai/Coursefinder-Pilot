import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";

// CF-247 / Decision 155 step 5: remove redundant copies of identical evidence files.
// Records were already pointed at the first stored copy (security.evidence_storage_dedupe_v1);
// this function (1) verifies a sample of copies byte-for-byte against the kept copy and
// (2) removes copies that no record references any more, logging each removal.
const VERSION="evidence-storage-dedupe-v1.0.0";
const FN="evidence-storage-dedupe";
const json=(b:unknown,s=200)=>new Response(JSON.stringify(b),{status:s,headers:{"content-type":"application/json","cache-control":"no-store"}});
async function rpc(c:any,n:string,a:Record<string,unknown>={}){const{data,error}=await c.rpc(n,a);if(error)throw new Error(`${n}: ${error.message}`);return data;}
async function sha(b:Uint8Array){const d=await crypto.subtle.digest("SHA-256",b);return[...new Uint8Array(d)].map(x=>x.toString(16).padStart(2,"0")).join("");}
async function download(svc:any,path:string){const{data,error}=await svc.storage.from("evidence").download(path);if(error||!data)throw new Error(`download ${path}: ${error?.message||"not found"}`);return new Uint8Array(await data.arrayBuffer());}

Deno.serve(async req=>{
  if(req.method!=="POST")return json({ok:false,error:"POST required"},405);
  const url=Deno.env.get("SUPABASE_URL")!,serviceKey=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,svc=createClient(url,serviceKey,{auth:{persistSession:false}});
  try{
    const nonce=(req.headers.get("x-cf-run-nonce")||"").trim(),bearer=(req.headers.get("authorization")||"").replace(/^Bearer\s+/i,"");
    if(nonce){if(!await rpc(svc,"svc_pilot_consume_nonce",{p_function:FN,p_nonce:nonce}))throw new Error("invalid, expired or already-used nonce");}
    else if(bearer!==serviceKey)throw new Error("service authorisation required");
    const body=await req.json().catch(()=>({})),started=Date.now();
    if(body.verify_sample){
      const n=Math.max(1,Math.min(Number(body.verify_sample)||10,30));
      const rows:any[]=await rpc(svc,"svc_evidence_dedupe_sample",{p_limit:n})||[];
      const results:any[]=[];const keeperHash=new Map<string,string>();
      for(const r of rows){
        try{
          if(!keeperHash.has(r.keeper_path))keeperHash.set(r.keeper_path,await sha(await download(svc,r.keeper_path)));
          const copy=await sha(await download(svc,r.path)),keep=keeperHash.get(r.keeper_path)!;
          results.push({path:r.path,identical:copy===keep&&keep===r.content_hash,copy_hash:copy.slice(0,12),keeper_hash:keep.slice(0,12),recorded_hash:String(r.content_hash).slice(0,12)});
        }catch(e){results.push({path:r.path,identical:false,error:String((e as Error).message||e)});}
        if(Date.now()-started>110000)break;
      }
      return json({ok:true,mode:"verify_sample",checked:results.length,identical:results.filter(x=>x.identical).length,results,workerVersion:VERSION});
    }
    if(body.remove){
      let removed=0,failed=0,batches=0;const limit=Math.max(1,Math.min(Number(body.limit)||100,100));
      while(Date.now()-started<100000){
        const paths:string[]=await rpc(svc,"svc_evidence_dedupe_next",{p_limit:limit})||[];
        if(!paths.length)break;
        const{error}=await svc.storage.from("evidence").remove(paths);
        if(error){failed+=paths.length;await rpc(svc,"svc_evidence_dedupe_mark",{p_paths:paths,p_ok:false,p_error:error.message});break;}
        removed+=await rpc(svc,"svc_evidence_dedupe_mark",{p_paths:paths,p_ok:true,p_error:null});batches++;
      }
      const left:string[]=await rpc(svc,"svc_evidence_dedupe_next",{p_limit:1})||[];
      return json({ok:true,mode:"remove",removed,failed,batches,more:left.length>0,ms:Date.now()-started,workerVersion:VERSION});
    }
    throw new Error("nothing to do: send verify_sample or remove");
  }catch(e){return json({ok:false,error:String((e as Error).message||e),workerVersion:VERSION},400);}
});
