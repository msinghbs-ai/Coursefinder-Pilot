-- Guards: Platform Admin 6 Nov 2026 09:44 section 5; accurate admitted/published measures.
-- Read-only production introspection 6 Nov 2026 11:10:38 UTC: exact existing consumer
-- visibility views and block-decision column types. No data copied. This fixture-only
-- dependency table seeds invented block events; it is not an admission path and
-- does not replace the manifest parity proof for the course-description path.
\set ON_ERROR_STOP 1
create table pipeline.layer4_block_decisions (
  id uuid,
  entity_type text,
  entity_id uuid,
  block_scope text,
  event_type text,
  reason_code text,
  comment text,
  actor_id uuid,
  actor_email text,
  expires_at timestamp with time zone,
  review_at timestamp with time zone,
  supersedes_decision_id uuid,
  approval_context jsonb,
  change_control_ref text,
  created_at timestamp with time zone
);

create view security.provider_hidden_v1 as
 SELECT id AS provider_id
   FROM catalogue.providers p
  WHERE publication_status IS DISTINCT FROM 'published'::text OR lifecycle_status IS DISTINCT FROM 'active'::text;

create view security.layer4_active_blocks as
 SELECT id,
    entity_type,
    entity_id,
    block_scope,
    reason_code,
    comment,
    actor_id,
    actor_email,
    expires_at,
    review_at,
    approval_context,
    created_at
   FROM ( SELECT DISTINCT ON (d.entity_type, d.entity_id, d.block_scope) d.id,
            d.entity_type,
            d.entity_id,
            d.block_scope,
            d.event_type,
            d.reason_code,
            d.comment,
            d.actor_id,
            d.actor_email,
            d.expires_at,
            d.review_at,
            d.approval_context,
            d.created_at
           FROM pipeline.layer4_block_decisions d
          ORDER BY d.entity_type, d.entity_id, d.block_scope, d.created_at DESC, d.id DESC) x
  WHERE event_type = 'block'::text AND (expires_at IS NULL OR expires_at > now());

create view security.layer4_search_blocked_courses as
 SELECT layer4_active_blocks.entity_id AS course_id
   FROM security.layer4_active_blocks
  WHERE layer4_active_blocks.block_scope = 'search'::text AND layer4_active_blocks.entity_type = 'course'::text
UNION
 SELECT c.id AS course_id
   FROM security.layer4_active_blocks b
     JOIN catalogue.courses c ON c.provider_id = b.entity_id
  WHERE b.block_scope = 'search'::text AND b.entity_type = 'provider'::text
UNION
 SELECT c.id AS course_id
   FROM security.provider_hidden_v1 h
     JOIN catalogue.courses c ON c.provider_id = h.provider_id
UNION
 SELECT c.id AS course_id
   FROM catalogue.courses c
  WHERE c.lifecycle_status IS DISTINCT FROM 'active'::text;
