-- Generated with Supabase CLI 2.122.0. Public RPC signatures stay compatible.
-- Privileged mutations live behind identity-checked helpers in the non-exposed schema.
begin;

create function social_private.save_social_profile(username text, display_name text, is_private boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 insert into public.climber_profiles values(auth.uid(),lower(trim(username)),trim(display_name),is_private,now())
 on conflict(id) do update set username=excluded.username,display_name=excluded.display_name,is_private=excluded.is_private,updated_at=now();
end;
$$;

revoke all on function social_private.save_social_profile(text,text,boolean) from public,anon;
grant execute on function social_private.save_social_profile(text,text,boolean) to authenticated;

create or replace function public.save_social_profile(username text, display_name text, is_private boolean) returns void
language sql security invoker set search_path='' as $$
 select social_private.save_social_profile($1,$2,$3);
$$;

revoke all on function public.save_social_profile(text,text,boolean) from public,anon;
grant execute on function public.save_social_profile(text,text,boolean) to authenticated;

create function social_private.friend_action(target uuid, action text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if auth.uid() is null or target=auth.uid() or social_private.blocked(target) then raise exception 'Unavailable'; end if;
 if action='request' then
   insert into public.friendships(requester,recipient) values(auth.uid(),target) on conflict do nothing;
 elsif action='accept' then
   update public.friendships set status='accepted' where requester=target and recipient=auth.uid() and status='pending';
 elsif action in ('remove','decline','cancel') then
   delete from public.friendships where (requester=auth.uid() and recipient=target) or (recipient=auth.uid() and requester=target);
 else raise exception 'Unknown action'; end if;
end;
$$;

revoke all on function social_private.friend_action(uuid,text) from public,anon;
grant execute on function social_private.friend_action(uuid,text) to authenticated;

create or replace function public.friend_action(target uuid, action text) returns void
language sql security invoker set search_path='' as $$
 select social_private.friend_action($1,$2);
$$;

revoke all on function public.friend_action(uuid,text) from public,anon;
grant execute on function public.friend_action(uuid,text) to authenticated;

create function social_private.save_shared_session(source_session_id uuid, visibility text, caption text, session_day text,
 attempts integer, sends integer, duration_minutes integer, completeness text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 insert into public.shared_sessions(owner_id,source_session_id,visibility,caption,session_day,attempts,sends,duration_minutes,completeness)
 values(auth.uid(),source_session_id,visibility,caption,session_day,attempts,sends,duration_minutes,completeness)
 on conflict on constraint shared_sessions_owner_id_source_session_id_key do update set visibility=excluded.visibility,caption=excluded.caption,
 session_day=excluded.session_day,attempts=excluded.attempts,sends=excluded.sends,duration_minutes=excluded.duration_minutes,
 completeness=excluded.completeness,updated_at=now();
end;
$$;

revoke all on function social_private.save_shared_session(uuid,text,text,text,integer,integer,integer,text) from public,anon;
grant execute on function social_private.save_shared_session(uuid,text,text,text,integer,integer,integer,text) to authenticated;

create or replace function public.save_shared_session(source_session_id uuid, visibility text, caption text, session_day text,
 attempts integer, sends integer, duration_minutes integer, completeness text) returns void
language sql security invoker set search_path='' as $$
 select social_private.save_shared_session($1,$2,$3,$4,$5,$6,$7,$8);
$$;

revoke all on function public.save_shared_session(uuid,text,text,text,integer,integer,integer,text) from public,anon;
grant execute on function public.save_shared_session(uuid,text,text,text,integer,integer,integer,text) to authenticated;

create function social_private.remove_shared_session(source_id uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 delete from public.shared_sessions where owner_id=auth.uid() and source_session_id=source_id;
end;
$$;

revoke all on function social_private.remove_shared_session(uuid) from public,anon;
grant execute on function social_private.remove_shared_session(uuid) to authenticated;

create or replace function public.remove_shared_session(source_id uuid) returns void
language sql security invoker set search_path='' as $$
 select social_private.remove_shared_session($1);
$$;

revoke all on function public.remove_shared_session(uuid) from public,anon;
grant execute on function public.remove_shared_session(uuid) to authenticated;

create function social_private.block_climber(target uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 insert into public.climber_blocks values(auth.uid(),target) on conflict do nothing;
 delete from public.friendships where (requester=auth.uid() and recipient=target) or (recipient=auth.uid() and requester=target);
end;
$$;

revoke all on function social_private.block_climber(uuid) from public,anon;
grant execute on function social_private.block_climber(uuid) to authenticated;

create or replace function public.block_climber(target uuid) returns void
language sql security invoker set search_path='' as $$
 select social_private.block_climber($1);
$$;

revoke all on function public.block_climber(uuid) from public,anon;
grant execute on function public.block_climber(uuid) to authenticated;

create function social_private.unblock_climber(target uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 delete from public.climber_blocks where owner_id=auth.uid() and target_id=target;
end;
$$;

revoke all on function social_private.unblock_climber(uuid) from public,anon;
grant execute on function social_private.unblock_climber(uuid) to authenticated;

create or replace function public.unblock_climber(target uuid) returns void
language sql security invoker set search_path='' as $$
 select social_private.unblock_climber($1);
$$;

revoke all on function public.unblock_climber(uuid) from public,anon;
grant execute on function public.unblock_climber(uuid) to authenticated;

create function social_private.report_climber(target uuid, reason text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 insert into public.social_reports(reporter,target_id,reason) values(auth.uid(),target,reason);
end;
$$;

revoke all on function social_private.report_climber(uuid,text) from public,anon;
grant execute on function social_private.report_climber(uuid,text) to authenticated;

create or replace function public.report_climber(target uuid, reason text) returns void
language sql security invoker set search_path='' as $$
 select social_private.report_climber($1,$2);
$$;

revoke all on function public.report_climber(uuid,text) from public,anon;
grant execute on function public.report_climber(uuid,text) to authenticated;

create function social_private.delete_social_profile() returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 delete from public.climber_profiles where id=auth.uid();
end;
$$;

revoke all on function social_private.delete_social_profile() from public,anon;
grant execute on function social_private.delete_social_profile() to authenticated;

create or replace function public.delete_social_profile() returns void
language sql security invoker set search_path='' as $$
 select social_private.delete_social_profile();
$$;

revoke all on function public.delete_social_profile() from public,anon;
grant execute on function public.delete_social_profile() to authenticated;

create function social_private.save_social_profile_v2(username text,display_name text,is_private boolean,bio text,avatar_base64 text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 perform public.save_social_profile(username,display_name,is_private);
 insert into public.climber_profile_details values(auth.uid(),trim(bio),avatar_base64,now())
 on conflict(id) do update set bio=excluded.bio,avatar_base64=excluded.avatar_base64,updated_at=now();
end;
$$;

revoke all on function social_private.save_social_profile_v2(text,text,boolean,text,text) from public,anon;
grant execute on function social_private.save_social_profile_v2(text,text,boolean,text,text) to authenticated;

create or replace function public.save_social_profile_v2(username text,display_name text,is_private boolean,bio text,avatar_base64 text) returns void
language sql security invoker set search_path='' as $$
 select social_private.save_social_profile_v2($1,$2,$3,$4,$5);
$$;

revoke all on function public.save_social_profile_v2(text,text,boolean,text,text) from public,anon;
grant execute on function public.save_social_profile_v2(text,text,boolean,text,text) to authenticated;

create function social_private.set_session_reaction(entry uuid,reaction text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if not exists(select 1 from public.shared_sessions s where s.id=entry and s.owner_id<>auth.uid()
 and social_private.visible_entry(s.owner_id,s.visibility)) then raise exception 'Entry unavailable'; end if;
 if reaction is null then delete from public.session_reactions where entry_id=entry and user_id=auth.uid();
 else insert into public.session_reactions values(entry,auth.uid(),reaction)
 on conflict(entry_id,user_id) do update set kind=excluded.kind; end if;
end $$;
revoke all on function social_private.set_session_reaction(uuid,text) from public,anon;
grant execute on function social_private.set_session_reaction(uuid,text) to authenticated;
create or replace function public.set_session_reaction(entry uuid,reaction text) returns void
language sql security invoker set search_path='' as $$
 select social_private.set_session_reaction($1,$2);
$$;
revoke all on function public.set_session_reaction(uuid,text) from public,anon;
grant execute on function public.set_session_reaction(uuid,text) to authenticated;

create index if not exists climber_blocks_target_idx on public.climber_blocks(target_id);
create index if not exists social_reports_reporter_idx on public.social_reports(reporter);
create index if not exists social_reports_target_idx on public.social_reports(target_id);
create index if not exists session_reactions_user_idx on public.session_reactions(user_id);
alter policy friendships_read on public.friendships using
 (((requester=(select auth.uid())) or (recipient=(select auth.uid()))) and
 not social_private.blocked(case when requester=(select auth.uid()) then recipient else requester end));
alter policy blocks_read on public.climber_blocks using(owner_id=(select auth.uid()));
alter policy details_read on public.climber_profile_details using
 (id=(select auth.uid()) or (not social_private.blocked(id) and
 (social_private.friends(id) or exists(select 1 from public.climber_profiles p where p.id=climber_profile_details.id and not p.is_private))));
-- Reports remain operator-only even if future client grants are added accidentally.
create policy reports_no_direct_client_access on public.social_reports as restrictive
for all to anon,authenticated using(false) with check(false);
notify pgrst,'reload schema';
commit;
