-- Guards: F-INT D3 forward fix: fixture-only tampering, installed one at a time on the fixture database, to prove each safeguard of migration 20261109170000 aborts and rolls back the whole change.
-- (psql variable `case` names the tampering.) Never part of a migration.
\set ON_ERROR_STOP on
\set QUIET on
create or replace function public.rb_tamper() returns trigger language plpgsql as $f$
declare v_pick uuid := (select intake_id from public.rb_cases where name = 'tamper_pick'); v_timed uuid := (select intake_id from public.rb_cases where name = 'already_timed');
begin
  if tg_table_name = 'course_intake_dates' then
    if new.intake_id = v_pick then
      if tg_argv[0] = 'row_checksum' then new.next_revisit_at := new.next_revisit_at + interval '1 microsecond'; return new; end if;
      if tg_argv[0] = 'other_column' then new.reason := coalesce(new.reason, '') || ' (tampered)'; return new; end if;
      if tg_argv[0] = 'other_row' then update pipeline.course_intake_dates set next_revisit_at = next_revisit_at + interval '1 day' where intake_id = v_timed; return new; end if;
      if tg_argv[0] = 'row_not_updated' then return null; end if;
    end if;
  elsif tg_table_name = 'intake_revisit_backfill_log' then
    if new.intake_id = v_pick and tg_argv[0] = 'log_value' then new.new_next_revisit_at := new.new_next_revisit_at + interval '1 microsecond'; end if;
  elsif tg_table_name = 'intake_revisit_backfill_batches' then
    if tg_argv[0] = 'batch_checksum' then new.checksum_expected := md5('tampered'); end if;
  end if;
  return new;
end $f$;
drop trigger if exists rb_tamper on pipeline.course_intake_dates;
drop trigger if exists rb_tamper on pipeline.intake_revisit_backfill_log;
drop trigger if exists rb_tamper on pipeline.intake_revisit_backfill_batches;
select case :'case'
  when 'row_checksum' then 'create trigger rb_tamper before update on pipeline.course_intake_dates for each row execute function public.rb_tamper(''row_checksum'')'
  when 'other_column' then 'create trigger rb_tamper before update on pipeline.course_intake_dates for each row execute function public.rb_tamper(''other_column'')'
  when 'other_row' then 'create trigger rb_tamper after update on pipeline.course_intake_dates for each row execute function public.rb_tamper(''other_row'')'
  when 'row_not_updated' then 'create trigger rb_tamper before update on pipeline.course_intake_dates for each row execute function public.rb_tamper(''row_not_updated'')'
  when 'log_value' then 'create trigger rb_tamper before insert on pipeline.intake_revisit_backfill_log for each row execute function public.rb_tamper(''log_value'')'
  when 'batch_checksum' then 'create trigger rb_tamper before insert on pipeline.intake_revisit_backfill_batches for each row execute function public.rb_tamper(''batch_checksum'')'
  else null end as ddl \gset
select :'ddl' is not null as known \gset
\if :known
:ddl;
\else
select 1/0;
\endif
