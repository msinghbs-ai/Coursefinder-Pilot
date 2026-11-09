-- Brings schema-prod.sql (generated from the live dump of 10 Oct 2026) to the live shape of 5 Nov 2026 for every relation the fixture
-- holds. Each difference was read from the live project (read-only pg_attribute, pg_index, pg_trigger, pg_constraint, pg_views) on
-- 5 Nov 2026 19:22-19:30 AEDT; check-live-parity.sql proves the result matches live (fingerprint per relation).
-- trigger functions of the triggers below (no-op bodies, live names; see the trigger note)
create or replace function security.provider_site_followups_tg() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
create or replace function security.provider_onboarding_new_tg() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
create or replace function security.course_description_review_trg_v1() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
create or replace function security.course_entry_review_trg_v1() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
create or replace function security.entry_matrix_review_trg_v1() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
create or replace function security.no_page_review_trg_v1() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
create or replace function security.provider_description_review_trg_v1() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
create or replace function security.layer4_reroute_trg_v1() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
create or replace function security.layer4_arrival_guard_trg_v1() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
create or replace function security.layer4_evidence_link_trg_v1() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
create or replace function security.ops_guard_layer4_v1() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
create or replace function security.ai_spend_capture_v1() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
create or replace function security.ops_guard_settings_v1() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
create or replace function pipeline.layer2_evidence_version_guard() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
create or replace function security.layer2_evidence_lineage_stamp() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
-- columns added or changed since 10 Oct
alter table catalogue.providers alter column publication_status set default 'published'::text;
alter table catalogue.providers add column provider_type_basis text, add column provider_type_set_at timestamp with time zone;
alter table pipeline.platform_toolset_settings add column used_by text;
alter table ref.study_levels add column short_code text;
alter table scholarship.course_mappings add column proof jsonb;
alter table scholarship.scholarships add column application_open_precision text, add column application_close_precision text,
  add column study_start_label text, add column study_start_date date;
-- pipeline.scholarship_ai_reviews (created after 10 Oct)
create sequence pipeline.scholarship_ai_reviews_id_seq;
create table pipeline.scholarship_ai_reviews (
  id bigint NOT NULL DEFAULT nextval('pipeline.scholarship_ai_reviews_id_seq'::regclass),
  candidate_id bigint,
  scholarship_id uuid,
  provider_id uuid,
  url text NOT NULL,
  storage_path text,
  extraction_ids bigint[] NOT NULL DEFAULT '{}'::bigint[],
  reason text NOT NULL,
  status text NOT NULL DEFAULT 'pending'::text,
  decided_by uuid,
  decided_at timestamp with time zone,
  note text,
  decision jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  recheck jsonb,
  constraint scholarship_ai_reviews_pkey PRIMARY KEY (id),
  constraint scholarship_ai_reviews_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'admitted'::text, 'refused'::text, 'superseded'::text]))));
alter sequence pipeline.scholarship_ai_reviews_id_seq owned by pipeline.scholarship_ai_reviews.id;
alter table pipeline.scholarship_ai_reviews enable row level security;
CREATE INDEX scholarship_ai_reviews_pending_idx ON pipeline.scholarship_ai_reviews USING btree (status, created_at);
CREATE INDEX scholarship_ai_reviews_url_idx ON pipeline.scholarship_ai_reviews USING btree (url, storage_path);
-- indexes added since 10 Oct
CREATE INDEX courses_not_active_idx ON catalogue.courses USING btree (id) WHERE (lifecycle_status IS DISTINCT FROM 'active'::text);
CREATE INDEX courses_provider_code_trim_active_idx ON catalogue.courses USING btree (provider_id, upper(btrim(course_code))) WHERE (lifecycle_status = 'active'::text);
CREATE INDEX courses_provider_title_slug_active_idx ON catalogue.courses USING btree (provider_id, replace(security.course_title_key(canonical_title), ' '::text, '-'::text)) WHERE (lifecycle_status = 'active'::text);
CREATE INDEX scholarships_provider_created_idx ON scholarship.scholarships USING btree (provider_id, created_at);
CREATE INDEX course_mappings_evidence_id_fk_idx ON scholarship.course_mappings USING btree (evidence_id);
CREATE INDEX layer4_review_items_entity_field_iq_idx ON pipeline.layer4_review_items USING btree (entity_id, field_code, status);
CREATE INDEX layer4_review_items_layer3_interpretation ON pipeline.layer4_review_items USING btree (layer3_interpretation_id) WHERE (layer3_interpretation_id IS NOT NULL);
CREATE UNIQUE INDEX layer4_review_items_course_entry_pending_uq ON pipeline.layer4_review_items USING btree (entity_id) WHERE ((field_code = 'course_entry_first_read'::text) AND (status = 'pending'::text));
-- index added since 5 Nov 2026 (found by the 9 Nov 2026 live re-check; an expression index on the live function security.site_host_v1, live/site_host_v1.sql)
CREATE INDEX providers_site_host_active_idx ON catalogue.providers USING btree (security.site_host_v1(website)) WHERE (lifecycle_status = 'active'::text);
-- triggers added since 10 Oct. provider_publish_by_default is the live function (live/provider_publish_by_default.sql): an active
-- provider is published on insert, so a fixture provider with the Published switch off is set by an update, as in production. The other
-- trigger functions act on writes this change never makes; they keep their live names with no-op bodies.
CREATE TRIGGER provider_publish_by_default BEFORE INSERT ON catalogue.providers FOR EACH ROW EXECUTE FUNCTION security.provider_publish_by_default();
CREATE TRIGGER provider_site_followups AFTER INSERT OR UPDATE OF website ON catalogue.providers FOR EACH ROW EXECUTE FUNCTION security.provider_site_followups_tg();
CREATE TRIGGER providers_onboarding_new AFTER INSERT ON catalogue.providers FOR EACH ROW EXECUTE FUNCTION security.provider_onboarding_new_tg();
CREATE TRIGGER layer4_review_items_course_description AFTER UPDATE OF status ON pipeline.layer4_review_items FOR EACH ROW WHEN (((old.status = 'pending'::text) AND (new.status <> 'pending'::text) AND (new.field_code = 'course_description_first_read'::text))) EXECUTE FUNCTION security.course_description_review_trg_v1();
CREATE TRIGGER layer4_review_items_course_entry AFTER UPDATE OF status ON pipeline.layer4_review_items FOR EACH ROW WHEN (((old.status = 'pending'::text) AND (new.status <> 'pending'::text) AND (new.field_code = 'course_entry_first_read'::text))) EXECUTE FUNCTION security.course_entry_review_trg_v1();
CREATE TRIGGER layer4_review_items_entry_matrix AFTER UPDATE OF status ON pipeline.layer4_review_items FOR EACH ROW WHEN (((old.status = 'pending'::text) AND (new.status <> 'pending'::text) AND (new.field_code = ANY (ARRAY['entry_matrix_first_run'::text, 'entry_matrix_change'::text])))) EXECUTE FUNCTION security.entry_matrix_review_trg_v1();
CREATE TRIGGER layer4_review_items_no_page AFTER UPDATE OF status ON pipeline.layer4_review_items FOR EACH ROW WHEN (((old.status = 'pending'::text) AND (new.status <> 'pending'::text) AND (new.field_code = ANY (ARRAY['no_page_first_run'::text, 'conjoint_rule_first_run'::text])))) EXECUTE FUNCTION security.no_page_review_trg_v1();
CREATE TRIGGER layer4_review_items_provider_description AFTER UPDATE OF status ON pipeline.layer4_review_items FOR EACH ROW WHEN (((old.status = 'pending'::text) AND (new.status <> 'pending'::text) AND (new.field_code = 'provider_description'::text))) EXECUTE FUNCTION security.provider_description_review_trg_v1();
CREATE TRIGGER layer4_review_items_reroute BEFORE INSERT ON pipeline.layer4_review_items FOR EACH ROW EXECUTE FUNCTION security.layer4_reroute_trg_v1();
CREATE TRIGGER layer4_review_items_zz_arrival BEFORE INSERT ON pipeline.layer4_review_items FOR EACH ROW EXECUTE FUNCTION security.layer4_arrival_guard_trg_v1();
CREATE TRIGGER layer4_review_items_zz_evidence BEFORE INSERT ON pipeline.layer4_review_items FOR EACH ROW EXECUTE FUNCTION security.layer4_evidence_link_trg_v1();
CREATE TRIGGER ops_guard_layer4 BEFORE INSERT OR DELETE OR UPDATE ON pipeline.layer4_review_items FOR EACH ROW WHEN (security.ops_remedy_guard_active_v1()) EXECUTE FUNCTION security.ops_guard_layer4_v1();
CREATE TRIGGER ai_spend_capture AFTER INSERT OR UPDATE OF recheck ON pipeline.scholarship_ai_reviews FOR EACH ROW EXECUTE FUNCTION security.ai_spend_capture_v1('scholarship_ai', 'delta', '{recheck,cost_usd}');
CREATE TRIGGER ops_guard_settings BEFORE INSERT OR DELETE OR UPDATE ON pipeline.platform_toolset_settings FOR EACH ROW WHEN (security.ops_remedy_guard_active_v1()) EXECUTE FUNCTION security.ops_guard_settings_v1();
-- views changed or added since 10 Oct (live text)
create view security.provider_hidden_v1 as
 SELECT id AS provider_id
   FROM catalogue.providers p
  WHERE ((publication_status IS DISTINCT FROM 'published'::text) OR (lifecycle_status IS DISTINCT FROM 'active'::text));
create or replace view security.layer4_search_blocked_courses as
 SELECT layer4_active_blocks.entity_id AS course_id
   FROM security.layer4_active_blocks
  WHERE ((layer4_active_blocks.block_scope = 'search'::text) AND (layer4_active_blocks.entity_type = 'course'::text))
UNION
 SELECT c.id AS course_id
   FROM (security.layer4_active_blocks b
     JOIN catalogue.courses c ON ((c.provider_id = b.entity_id)))
  WHERE ((b.block_scope = 'search'::text) AND (b.entity_type = 'provider'::text))
UNION
 SELECT c.id AS course_id
   FROM (security.provider_hidden_v1 h
     JOIN catalogue.courses c ON ((c.provider_id = h.provider_id)))
UNION
 SELECT c.id AS course_id
   FROM catalogue.courses c
  WHERE (c.lifecycle_status IS DISTINCT FROM 'active'::text);
create or replace view security.layer4_search_blocked_providers as
 SELECT layer4_active_blocks.entity_id AS provider_id
   FROM security.layer4_active_blocks
  WHERE ((layer4_active_blocks.block_scope = 'search'::text) AND (layer4_active_blocks.entity_type = 'provider'::text))
UNION
 SELECT h.provider_id
   FROM security.provider_hidden_v1 h;
create or replace view security.layer4_search_blocked_scholarships as
 SELECT layer4_active_blocks.entity_id AS scholarship_id
   FROM security.layer4_active_blocks
  WHERE ((layer4_active_blocks.block_scope = 'search'::text) AND (layer4_active_blocks.entity_type = 'scholarship'::text))
UNION
 SELECT s.id AS scholarship_id
   FROM (security.layer4_active_blocks b
     JOIN scholarship.scholarships s ON ((s.provider_id = b.entity_id)))
  WHERE ((b.block_scope = 'search'::text) AND (b.entity_type = 'provider'::text))
UNION
 SELECT s.id AS scholarship_id
   FROM (security.provider_hidden_v1 h
     JOIN scholarship.scholarships s ON ((s.provider_id = h.provider_id)));
-- secondary tables (foreign-key targets): indexes and triggers changed since 10 Oct
CREATE INDEX evidence_artifacts_source_url_pattern_idx ON pipeline.evidence_artifacts USING btree (lower(source_url) text_pattern_ops);
CREATE INDEX course_financial_calculations_fee_evidence_id_fk_idx ON scholarship.course_financial_calculations USING btree (fee_evidence_id);
CREATE INDEX course_financial_calculations_scholarship_evidence_id_fk_idx ON scholarship.course_financial_calculations USING btree (scholarship_evidence_id);
-- three indexes of 10 Oct that live no longer has (fixture database only)
drop index pipeline.evidence_job_idx; drop index pipeline.evidence_layer2_profile_version_idx; drop index pipeline.layer2_evidence_review_idx;
create or replace function security.course_fee_identity_gate_tg() returns trigger language plpgsql as $t$ begin if tg_op = 'DELETE' then return old; end if; return new; end $t$;
CREATE TRIGGER course_fee_identity_gate BEFORE INSERT OR UPDATE ON catalogue.course_fees FOR EACH ROW EXECUTE FUNCTION security.course_fee_identity_gate_tg();
