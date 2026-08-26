import "jsr:@supabase/functions-js/edge-runtime.d.ts";

Deno.serve(() => new Response(
  JSON.stringify({ error: 'benchmark_completed', state: 'retired' }),
  {
    status: 410,
    headers: {
      'content-type': 'application/json',
      'cache-control': 'no-store',
    },
  },
));
