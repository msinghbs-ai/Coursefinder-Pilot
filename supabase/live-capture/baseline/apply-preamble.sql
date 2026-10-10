-- CF-247 production readiness phase 4 (10 Oct 2026): run before schema.sql when building a new project.
-- A new Supabase project gives anon, authenticated and service_role every privilege on new objects in public
-- (default privileges of the postgres role). pg_dump writes each object's grants as they are, but never
-- revokes what default privileges add, so without this preamble a rebuilt project would let anon run
-- 640 functions and read 10 tables that the Pilot does not expose (rebuild run 38028086660).
-- These defaults are removed only while the objects are created; the closing ALTER DEFAULT PRIVILEGES
-- statements in schema.sql put the Pilot's defaults back.
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM "anon", "authenticated", "service_role";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES FROM "anon", "authenticated", "service_role";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "anon", "authenticated", "service_role";
