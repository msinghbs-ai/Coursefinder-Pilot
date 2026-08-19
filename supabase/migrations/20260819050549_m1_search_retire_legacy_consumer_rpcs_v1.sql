revoke execute on function api.search_courses(text,character,text,boolean,integer) from authenticated;
revoke execute on function api.vector_candidates(extensions.vector,text,character,text,integer) from authenticated;
grant execute on function api.search_courses(text,character,text,boolean,integer) to service_role;
grant execute on function api.vector_candidates(extensions.vector,text,character,text,integer) to service_role;
comment on function api.search_courses(text,character,text,boolean,integer) is 'DEPRECATED internal service-only Search RPC. Consumer integrations must use versioned M1-SEARCH contracts.';
comment on function api.vector_candidates(extensions.vector,text,character,text,integer) is 'DEPRECATED internal service-only vector RPC. Semantic consumer access requires the M1-SEARCH vector gate and versioned contract.';
