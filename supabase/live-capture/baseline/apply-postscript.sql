-- CF-247 production readiness phase 4 (10 Oct 2026): run after schema.sql when building a new project.
-- The Supabase CLI schema dump leaves out the grant lines of functions whose arguments use an extension type
-- (here pgvector's extensions.vector), so on a rebuilt project these three functions kept the default
-- EXECUTE for PUBLIC (anon and authenticated) - rebuild run 38028894493. The Pilot allows only service_role.
REVOKE ALL ON FUNCTION "api"."query_embedding_cache_put"("text", "text", "text", "extensions"."vector", integer) FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "api"."query_embedding_cache_put"("text", "text", "text", "extensions"."vector", integer) TO "service_role";
REVOKE ALL ON FUNCTION "api"."vector_candidates"("extensions"."vector", "text", character, "text", integer) FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "api"."vector_candidates"("extensions"."vector", "text", character, "text", integer) TO "service_role";
REVOKE ALL ON FUNCTION "search"."course_candidates_v1"("text", "extensions"."vector", "text", "text", "text", "text"[], "text"[], "text"[], "text"[], "text"[], boolean, boolean, "text"[], integer) FROM PUBLIC, "anon", "authenticated";
GRANT ALL ON FUNCTION "search"."course_candidates_v1"("text", "extensions"."vector", "text", "text", "text", "text"[], "text"[], "text"[], "text"[], "text"[], boolean, boolean, "text"[], integer) TO "service_role";
