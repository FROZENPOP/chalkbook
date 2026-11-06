-- Server-side input checks for anything another climber can see. Every RPC here can be called
-- directly with a user token, so these can't rely on the app's own checks.
begin;
-- NOT VALID: new and edited rows are checked; rows saved before this migration are left alone.
alter table public.climber_profiles
 add constraint display_name_visible check (display_name ~ '[^[:space:]\u00a0\u200b-\u200d\u2060\ufeff]') not valid,
 -- Control, zero-width and text-direction characters can hide or spoof a name.
 add constraint display_name_plain check (display_name !~ '[[:cntrl:]\u200b-\u200f\u202a-\u202e\u2060\u2066-\u2069\ufeff]') not valid,
 add constraint display_name_not_staff check (display_name !~* 'chalkbook') not valid,
 add constraint username_not_reserved check (username !~ 'chalkbook' and username not in
  ('admin','administrator','moderator','mod','support','help','official','staff','team','security','apple')) not valid;
alter table public.session_comments
 add constraint body_visible check (body ~ '[^[:space:]\u00a0\u200b-\u200d\u2060\ufeff]') not valid;
alter table public.social_reports
 add constraint reason_visible check (reason ~ '[^[:space:]\u00a0\u200b-\u200d\u2060\ufeff]') not valid;
-- The app only uploads JPEG avatars.
alter table public.climber_profile_details
 add constraint avatar_is_jpeg check (avatar_base64 is null or substring(decode(avatar_base64,'base64') from 1 for 3)=decode('ffd8ff','hex')) not valid;

-- Checks that depend on today's date or on how much a climber has already posted.
create function social_private.limit_input() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 if tg_table_name='shared_sessions' then
  -- The feed is newest day first, so a far-future day would pin a post to the top.
  if new.session_day::date not between date '2000-01-01' and current_date+2 then raise exception 'Invalid session day'; end if;
  if tg_op='INSERT' and (select count(*) from public.shared_sessions s where s.owner_id=new.owner_id)>=2000 then
   raise exception 'Shared session limit reached'; end if;
 elsif tg_table_name='session_comments' then
  if (select count(*) from public.session_comments c where c.user_id=new.user_id and c.created_at>now()-interval '1 minute')>=10 then
   raise exception 'Too many comments, try again in a minute'; end if;
 elsif tg_table_name='social_reports' then
  if (select count(*) from public.social_reports r where r.reporter=new.reporter and r.created_at>now()-interval '1 day')>=20 then
   raise exception 'Too many reports today'; end if;
 end if;
 return new;
end $$;
revoke all on function social_private.limit_input() from public,anon,authenticated;
create trigger limit_shared_session before insert or update on public.shared_sessions for each row execute function social_private.limit_input();
create trigger limit_comment before insert on public.session_comments for each row execute function social_private.limit_input();
create trigger limit_report before insert on public.social_reports for each row execute function social_private.limit_input();

-- Each report can ping the moderator once, so the report-alert function can't be used to spam them.
alter table public.social_reports add column alerted boolean not null default false;
create function social_private.claim_report_alert() returns boolean
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then return false; end if;
 update public.social_reports r set alerted=true
  where r.reporter=auth.uid() and not r.alerted and r.created_at>now()-interval '5 minutes';
 return found;
end $$;
revoke all on function social_private.claim_report_alert() from public,anon;
grant execute on function social_private.claim_report_alert() to authenticated;
create function public.claim_report_alert() returns boolean
language sql security invoker set search_path='' as $$ select social_private.claim_report_alert(); $$;
revoke all on function public.claim_report_alert() from public,anon;
grant execute on function public.claim_report_alert() to authenticated;
commit;
