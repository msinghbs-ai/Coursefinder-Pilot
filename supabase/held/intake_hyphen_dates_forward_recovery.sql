-- HELD (not a migration): forward recovery for 20261110110523 (the intake page route, its hint and the plan's page-date guard read "01-March-2027" as well as "1 March 2027").
-- Run only if the Platform Admin decides to go back to the earlier text. It puts back, byte for byte, the bodies of security.intake_page_date_hint_v1(uuid,uuid,text) (body md5
-- 6adf9102074633735e9f30ffe529072c), security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer) (52bad9ded722b889b97c746b7209e63a) and
-- security.intake_dates_plan_v3(uuid[],integer) (06255497ef431b0ae0d9fca6460c6cb5) as they were before that migration, each guarded by the md5 of what is live now: it changes nothing if a
-- live body is neither its earlier text nor the one the migration wrote (7e008fa7981cf32ab89765829b7a3439, de956842ab53e842c7b4baaf578ff0f0 and 33e3fef045dbcfa8a0406c64402d4d29).
-- Decisions, events, settings and dates already admitted are not touched: a date admitted from a hyphenated page date stays, with its rule and quote; to take dates back use the governed
-- withdrawal (public.admin_intake_date_withdraw_v1). Running it twice changes nothing. The migration applies again after it.

do $g$
declare r record; v text;
begin
  for r in select * from (values ('security.intake_page_date_hint_v1(uuid,uuid,text)', '6adf9102074633735e9f30ffe529072c', '7e008fa7981cf32ab89765829b7a3439'),
                                 ('security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)', '52bad9ded722b889b97c746b7209e63a', 'de956842ab53e842c7b4baaf578ff0f0'),
                                 ('security.intake_dates_plan_v3(uuid[],integer)', '06255497ef431b0ae0d9fca6460c6cb5', '33e3fef045dbcfa8a0406c64402d4d29')) x(sig, earlier, written) loop
    select md5(p.prosrc) into v from pg_proc p where p.oid = to_regprocedure(r.sig);
    if v is null then raise exception '% is missing', r.sig; end if;
    if v not in (r.earlier, r.written) then raise exception 'live % differs from both texts this recovery knows (body md5 %)', r.sig, v; end if;
  end loop;
end $g$;

create or replace function pg_temp.restore(p_sig text, p_now text, p_earlier text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig::regprocedure), chr(13), ''); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  if md5(v_src) = p_earlier then raise notice '%: nothing to restore', p_sig; return p_sig || ': nothing to restore'; end if;
  if md5(v_src) <> p_now then raise exception 'live % differs from both texts this recovery knows (body md5 %)', p_sig, md5(v_src); end if;
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_earlier then raise exception '% after the restore has body md5 %, expected %', p_sig, md5(v_src), p_earlier; end if;
  raise notice '%: restored', p_sig;
  return p_sig || ': restored';
end $f$;

select pg_temp.restore('security.intake_page_date_hint_v1(uuid,uuid,text)', '7e008fa7981cf32ab89765829b7a3439', '6adf9102074633735e9f30ffe529072c',
  array[$n$(?:st|nd|rd|th)?(?:\s+|-)' || v_mon || '\.?(?:,?\s+|-)20\d\d\M')$n$],
  array[$o$(?:st|nd|rd|th)?\s+' || v_mon || '\.?,?\s+20\d\d\M')$o$]);

select pg_temp.restore('security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)', 'de956842ab53e842c7b4baaf578ff0f0', '52bad9ded722b889b97c746b7209e63a',
  array[$n$(?:st|nd|rd|th)?(?:\s+|-)' || v_mon || '\.?(?:,?\s+|-)(20\d\d)\M(?!\s*:))'$n$],
  array[$o$(?:st|nd|rd|th)?\s+' || v_mon || '\.?,?\s+(20\d\d)\M(?!\s*:))'$o$]);

select pg_temp.restore('security.intake_dates_plan_v3(uuid[],integer)', '33e3fef045dbcfa8a0406c64402d4d29', '06255497ef431b0ae0d9fca6460c6cb5',
  array[$n$(?:st|nd|rd|th)?(?:\s+|-)' || (array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])[v_m] || '[a-z]*(?:,?\s+|-)' || v_year || '\M'$n$],
  array[$o$(?:st|nd|rd|th)?\s+' || (array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])[v_m] || '[a-z]*,?\s+' || v_year || '\M'$o$]);
