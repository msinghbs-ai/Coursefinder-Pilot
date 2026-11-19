-- M1-PIM-FINALISATION: narrow covering index for browser Search/Publication counters.
-- Avoids cold scans of wide search.course_documents rows; no Search semantics change.
create index if not exists search_course_documents_admin_summary_idx
  on search.course_documents(publication_status,has_fee,has_intake,has_english,has_scholarship,generated_at);
analyze search.course_documents;
