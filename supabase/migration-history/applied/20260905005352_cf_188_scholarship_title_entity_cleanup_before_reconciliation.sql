update pipeline.scholarship_source_records
set payload=jsonb_set(payload,'{name}',to_jsonb(replace(replace(replace(payload->>'name','&#x2019;','’'),'&#x27;',''''),'&amp;','&')))
where status='captured' and payload->>'name' ~ '&(#x2019|#x27|amp);';
