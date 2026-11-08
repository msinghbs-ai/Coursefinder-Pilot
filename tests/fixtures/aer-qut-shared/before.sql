-- the shared-page lists BEFORE migration 20261108030000 (the live rule), kept for the scenarios
create table t.shared_before as select n.name, jsonb_array_length(security.course_entry_shared_page_v1(n.id)) n from t.named n where n.name ~ '^[ABC][0-9]$';
select format('before: A1 %s A2 %s A4 %s A5 %s A8 %s A9 %s', (select n from t.shared_before where name='A1'), (select n from t.shared_before where name='A2'), (select n from t.shared_before where name='A4'),
              (select n from t.shared_before where name='A5'), (select n from t.shared_before where name='A8'), (select n from t.shared_before where name='A9'));
