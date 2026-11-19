alter table ranking.manual_imports alter column uploaded_by drop not null;
comment on column ranking.manual_imports.uploaded_by is 'Authenticated operator when interactive; NULL for governed system acquisition. Evidence/job metadata preserves acquisition actor type.';
