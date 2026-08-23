import "jsr:@supabase/functions-js/edge-runtime.d.ts";
Deno.serve(() => new Response(JSON.stringify({status:"retired",gate:"M1-SECURITY-RELEASE",reason:"Legacy CA diagnostic/probe/audit surface retired under CF-CHG-20260823-027."}),{status:410,headers:{"content-type":"application/json","cache-control":"no-store"}}));
