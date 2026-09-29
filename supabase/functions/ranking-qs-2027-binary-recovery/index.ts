import "jsr:@supabase/functions-js/edge-runtime.d.ts";
// Retired 29 Sep 2026 (CF-247 production readiness): one-off QS 2027 recovery from Sep 2026 (its access key was embedded in source).
Deno.serve(() => new Response(JSON.stringify({status:"retired",gate:"CF-247-PRODUCTION-READINESS",reason:"One-off QS 2027 recovery completed in September 2026; endpoint retired."}),{status:410,headers:{"content-type":"application/json","cache-control":"no-store"}}));
