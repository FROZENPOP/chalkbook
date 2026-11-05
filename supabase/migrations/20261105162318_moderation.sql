-- Filters objectionable text before it is posted, ties reports to the exact comment or post,
-- and keeps reports when either account is deleted (App Store Guideline 1.2).
begin;

-- shortcut: a short word list only stops the obvious cases, upgrade to a moderation service if reports show it misses too much.
create function social_private.reject_objectionable() returns trigger
language plpgsql set search_path='' as $$
declare
 field text;
 value text;
begin
 foreach field in array tg_argv loop
  -- Undo simple letter swaps like "k1ll". Only used for matching; the saved text is untouched.
  value:=translate(lower(coalesce(to_jsonb(new)->>field,'')),'013457@$','oieastas');
  if value ~ '\y(nigg(er|a)s?|fagg?(ot)?s?|kikes?|spics?|wetbacks?|trann(y|ies)|gooks?|ragheads?|retards?|cunts?|rap(e|ing|ist)|blowjobs?|porn|pedos?|kill yourself|kys|go die)\y' then
   raise exception 'Content not allowed' using errcode='SN001';
  end if;
 end loop;
 return new;
end $$;
revoke all on function social_private.reject_objectionable() from public,anon,authenticated;

create trigger filter_comment before insert or update on public.session_comments
 for each row execute function social_private.reject_objectionable('body');
create trigger filter_caption before insert or update on public.shared_sessions
 for each row execute function social_private.reject_objectionable('caption');
create trigger filter_profile before insert or update on public.climber_profiles
 for each row execute function social_private.reject_objectionable('username','display_name');
create trigger filter_bio before insert or update on public.climber_profile_details
 for each row execute function social_private.reject_objectionable('bio');

-- A report must outlive both accounts, or a reported climber could erase it by deleting theirs.
alter table public.social_reports
 drop constraint social_reports_reporter_fkey,
 drop constraint social_reports_target_id_fkey,
 alter column reporter drop not null,
 alter column target_id drop not null,
 add constraint social_reports_reporter_fkey foreign key(reporter) references auth.users(id) on delete set null,
 add constraint social_reports_target_id_fkey foreign key(target_id) references public.climber_profiles(id) on delete set null,
 add column target_username text,
 -- Copies, not references, so the evidence survives the content being deleted.
 add column comment_id uuid,
 add column entry_id uuid,
 add column content text,
 add column reviewed_at timestamptz;
update public.social_reports r set target_username=p.username from public.climber_profiles p where p.id=r.target_id;

drop function public.report_climber(uuid,text);
drop function social_private.report_climber(uuid,text);

create function social_private.report_climber(target uuid,reason text,comment uuid,entry uuid) returns void
language plpgsql security definer set search_path='' as $$
declare
 reported text;
 entry_found uuid:=entry;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 -- Only content this reporter can see, and only if it belongs to the climber being reported.
 if comment is not null then
  select c.body,c.entry_id into reported,entry_found from public.session_comments c
  join public.shared_sessions s on s.id=c.entry_id
  where c.id=comment and c.user_id=target and social_private.visible_entry(s.owner_id,s.visibility);
  if not found then raise exception 'Content unavailable'; end if;
 elsif entry is not null then
  select s.caption into reported from public.shared_sessions s
  where s.id=entry and s.owner_id=target and social_private.visible_entry(s.owner_id,s.visibility);
  if not found then raise exception 'Content unavailable'; end if;
 end if;
 -- shortcut: old reports are purged only when a new one arrives, add a scheduled job once reports are frequent.
 delete from public.social_reports r where r.created_at<now()-interval '12 months';
 insert into public.social_reports(reporter,target_id,target_username,reason,comment_id,entry_id,content)
 select auth.uid(),target,p.username,reason,comment,entry_found,reported from public.climber_profiles p where p.id=target;
 if not found then raise exception 'Climber unavailable'; end if;
end $$;
revoke all on function social_private.report_climber(uuid,text,uuid,uuid) from public,anon;
grant execute on function social_private.report_climber(uuid,text,uuid,uuid) to authenticated;

-- Same two-argument call still works, so app versions without per-post reports keep reporting.
create function public.report_climber(target uuid,reason text,comment uuid default null,entry uuid default null) returns void
language sql security invoker set search_path='' as $$
 select social_private.report_climber($1,$2,$3,$4);
$$;
revoke all on function public.report_climber(uuid,text,uuid,uuid) from public,anon;
grant execute on function public.report_climber(uuid,text,uuid,uuid) to authenticated;

commit;
