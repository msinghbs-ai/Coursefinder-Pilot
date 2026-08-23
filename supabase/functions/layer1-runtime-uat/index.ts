import "jsr:@supabase/functions-js/edge-runtime.d.ts";
Deno.serve(() => new Response(JSON.stringify({status:"retired",gate:"M1-SECURITY-RELEASE",reason:"Legacy diagnostic/UAT Edge surface retired under CF-CHG-20260823-027; use governed automated browser UAT."}),{status:410,headers:{"content-type":"application/json","cache-control":"no-store"}}));
