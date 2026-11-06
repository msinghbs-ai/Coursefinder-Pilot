-- Guards: Provider Description mandate §8–9: captured relevant Zoho dependency triggers.
CREATE TRIGGER evidence_entity_links_sync AFTER INSERT OR DELETE OR UPDATE ON catalogue.course_campuses FOR EACH ROW EXECUTE FUNCTION security.sync_evidence_entity_links();
CREATE TRIGGER evidence_entity_links_sync AFTER INSERT OR DELETE OR UPDATE ON catalogue.campuses FOR EACH ROW EXECUTE FUNCTION security.sync_evidence_entity_links();
CREATE TRIGGER evidence_lineage_stats_sync AFTER INSERT OR DELETE OR UPDATE ON catalogue.course_campuses FOR EACH ROW EXECUTE FUNCTION security.sync_evidence_lineage_stats();
CREATE TRIGGER evidence_lineage_stats_sync AFTER INSERT OR DELETE OR UPDATE ON catalogue.campuses FOR EACH ROW EXECUTE FUNCTION security.sync_evidence_lineage_stats();
CREATE TRIGGER manual_lock_guard BEFORE UPDATE ON catalogue.campuses FOR EACH ROW EXECUTE FUNCTION security.manual_column_guard('campus');