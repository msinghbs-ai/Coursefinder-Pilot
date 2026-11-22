-- CF-247 S2-Build trial (never merged; rolled back). Replaces: nothing. Retires: nothing.
create index if not exists course_documents_title_trgm_idx on search.course_documents using gin (course_title extensions.gin_trgm_ops);
create index if not exists course_documents_provider_name_trgm_idx on search.course_documents using gin (provider_name extensions.gin_trgm_ops);
analyze search.course_documents;
