import "jsr:@supabase/functions-js/edge-runtime.d.ts";

/**
 * AU full-ingestion UAT helper.
 *
 * The full AU CRICOS phase gate completed on 2026-08-12. The temporary
 * unauthenticated/batched UAT runner is intentionally disabled after sign-off.
 * Production/admin execution must use the authenticated Layer 1 worker path.
 */
Deno.serve(() => new Response(JSON.stringify({
  ok: false,
  status: "disabled",
  message: "AU full-ingestion phase-gate runner is disabled after successful Layer 1 UAT. Use the approved authenticated Layer 1 operational worker."
}), {
  status: 410,
  headers: {
    "content-type": "application/json",
    "cache-control": "no-store"
  }
}));
