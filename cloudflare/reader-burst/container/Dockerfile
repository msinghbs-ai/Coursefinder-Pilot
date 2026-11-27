# Reader container image (CF-247 s1320, S1-Build, 27 Nov 2026). PREPARED, NOT DEPLOYED: HELD:DEPLOYMENT_APPROVAL.
# Build context is the repository root (wrangler.jsonc images.reader.build_context "../.."), so the existing reader modules are copied
# byte for byte from supabase/functions/coverage-sweep. linux/amd64, pinned base, non-root, dependencies cached at build time
# (the container runs with enableInternet false).
FROM --platform=linux/amd64 denoland/deno:debian-2.1.4
WORKDIR /app
COPY supabase/functions/coverage-sweep/pdf.ts supabase/functions/coverage-sweep/entry-pdf-scope.ts ./reader/
COPY cloudflare/reader-burst/container/server.ts ./server.ts
RUN deno cache --allow-import server.ts && chown -R deno:deno /app
USER deno
EXPOSE 8080
CMD ["run", "--cached-only", "--allow-net=0.0.0.0:8080", "--allow-read=/app", "--allow-env", "server.ts"]
