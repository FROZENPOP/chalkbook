-- Stop bulk listing of every climber. The table now shows only climbers you're connected to or whose
-- posts or comments you can see. Anyone else is looked up one at a time by id (search, suggestions, invites).
begin;
create function social_private.profile_visible(target uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select target=auth.uid()
  or exists(select 1 from public.friendships f where (f.requester=auth.uid() and f.recipient=target) or (f.recipient=auth.uid() and f.requester=target))
  or exists(select 1 from public.shared_sessions s where s.owner_id=target and social_private.visible_entry(s.owner_id,s.visibility))
  or exists(select 1 from public.session_comments c join public.shared_sessions s on s.id=c.entry_id
   where c.user_id=target and social_private.visible_entry(s.owner_id,s.visibility))
$$;
revoke all on function social_private.profile_visible(uuid) from public,anon;
grant execute on function social_private.profile_visible(uuid) to authenticated;
drop policy profiles_read on public.climber_profiles;
create policy profiles_read on public.climber_profiles for select to authenticated
 using(not social_private.blocked(id) and social_private.profile_visible(id));

create function social_private.climber_profile(target uuid) returns setof public.climber_profiles
language sql stable security definer set search_path='' as $$
 select p.* from public.climber_profiles p where p.id=target and auth.uid() is not null and not social_private.blocked(p.id)
$$;
revoke all on function social_private.climber_profile(uuid) from public,anon;
grant execute on function social_private.climber_profile(uuid) to authenticated;
create function public.climber_profile(target uuid) returns setof public.climber_profiles
language sql stable security invoker set search_path='' as $$ select * from social_private.climber_profile($1); $$;
revoke all on function public.climber_profile(uuid) from public,anon;
grant execute on function public.climber_profile(uuid) to authenticated;
commit;
