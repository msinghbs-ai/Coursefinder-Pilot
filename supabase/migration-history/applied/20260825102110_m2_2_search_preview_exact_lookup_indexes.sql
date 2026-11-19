create index if not exists course_documents_course_code_lower_idx on search.course_documents (lower(course_code)) where course_code is not null;
create index if not exists course_documents_stable_key_lower_idx on search.course_documents (lower(course_stable_key)) where course_stable_key is not null;
create index if not exists course_documents_title_lower_idx on search.course_documents (lower(course_title));
create index if not exists course_documents_provider_name_lower_idx on search.course_documents (lower(provider_name));
create index if not exists course_documents_provider_stable_key_idx on search.course_documents (provider_stable_key) where provider_stable_key is not null;
