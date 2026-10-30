-- Additive, opt-out discovery. No new access to friendship rows or private avatars.
begin;
create table public.friend_discovery_settings (
 owner_id uuid primary key references public.climber_profiles(id) on delete cascade,
 enabled boolean not null default true
);
create table public.friend_suggestion_dismissals (
 owner_id uuid not null references public.climber_profiles(id) on delete cascade,
 target_id uuid not null references public.climber_profiles(id) on delete cascade,
 primary key(owner_id,target_id), check(owner_id<>target_id)
);
create index friend_suggestion_dismissals_target on public.friend_suggestion_dismissals(target_id);
alter table public.friend_discovery_settings enable row level security;
alter table public.friend_suggestion_dismissals enable row level security;
create policy discovery_owner_read on public.friend_discovery_settings for select to authenticated using(owner_id=(select auth.uid()));
create policy dismissals_owner_read on public.friend_suggestion_dismissals for select to authenticated using(owner_id=(select auth.uid()));
revoke all on public.friend_discovery_settings, public.friend_suggestion_dismissals from public,anon,authenticated;
grant select on public.friend_discovery_settings, public.friend_suggestion_dismissals to authenticated;

create function social_private.set_friend_discovery(enabled boolean) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if enabled is null then raise exception 'Setting required'; end if;
 insert into public.friend_discovery_settings(owner_id,enabled) values(auth.uid(),enabled)
 on conflict(owner_id) do update set enabled=excluded.enabled;
end;
$$;
create function social_private.dismiss_friend_suggestion(target uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if target is null or target=auth.uid() then raise exception 'Unavailable'; end if;
 insert into public.friend_suggestion_dismissals(owner_id,target_id) values(auth.uid(),target) on conflict do nothing;
end;
$$;
create function social_private.suggested_friends(p_limit integer default 10,p_offset integer default 0)
returns table(id uuid,display_name text,avatar_base64 text,mutual_count bigint,mutual_names text[])
language plpgsql stable security definer set search_path='' as $$
declare viewer uuid:=auth.uid();
begin
 if viewer is null then raise exception 'Sign in required'; end if;
 return query
 with edges as (
  select f.requester as owner,f.recipient as friend from public.friendships f where f.status='accepted'
  union all
  select f.recipient,f.requester from public.friendships f where f.status='accepted'
 ), mutuals as (
  select distinct next.friend as candidate,first.friend as mutual
  from edges first join edges next on next.owner=first.friend
  where first.owner=viewer and next.friend<>viewer
   and not social_private.blocked(first.friend)
   and not exists(select 1 from public.climber_blocks b where
    (b.owner_id=first.friend and b.target_id=next.friend) or (b.target_id=first.friend and b.owner_id=next.friend))
 ), ranked as (
  select m.candidate,count(*) as total from mutuals m
  join public.climber_profiles p on p.id=m.candidate
  left join public.friend_discovery_settings s on s.owner_id=m.candidate
  where coalesce(s.enabled,true) and not social_private.blocked(m.candidate)
   and not exists(select 1 from public.friendships f where
    (f.requester=viewer and f.recipient=m.candidate) or (f.recipient=viewer and f.requester=m.candidate))
   and not exists(select 1 from public.friend_suggestion_dismissals d where d.owner_id=viewer and d.target_id=m.candidate)
  group by m.candidate
  order by count(*) desc,m.candidate
  limit least(20,greatest(1,coalesce(p_limit,10))) offset least(10000,greatest(0,coalesce(p_offset,0)))
 )
 select p.id,p.display_name,case when not p.is_private then details.avatar_base64 else null end,r.total,
  array(select mutual_profile.display_name from mutuals m join public.climber_profiles mutual_profile on mutual_profile.id=m.mutual
   where m.candidate=r.candidate order by mutual_profile.display_name,mutual_profile.id limit 3)
 from ranked r join public.climber_profiles p on p.id=r.candidate
 left join public.climber_profile_details details on details.id=p.id
 order by r.total desc,p.id;
end;
$$;
revoke all on function social_private.set_friend_discovery(boolean),social_private.dismiss_friend_suggestion(uuid),social_private.suggested_friends(integer,integer) from public,anon;
grant execute on function social_private.set_friend_discovery(boolean),social_private.dismiss_friend_suggestion(uuid),social_private.suggested_friends(integer,integer) to authenticated;

create function public.set_friend_discovery(enabled boolean) returns void
language sql security invoker set search_path='' as $$ select social_private.set_friend_discovery($1); $$;
create function public.dismiss_friend_suggestion(target uuid) returns void
language sql security invoker set search_path='' as $$ select social_private.dismiss_friend_suggestion($1); $$;
create function public.suggested_friends(p_limit integer default 10,p_offset integer default 0)
returns table(id uuid,display_name text,avatar_base64 text,mutual_count bigint,mutual_names text[])
language sql stable security invoker set search_path='' as $$ select * from social_private.suggested_friends($1,$2); $$;
revoke all on function public.set_friend_discovery(boolean),public.dismiss_friend_suggestion(uuid),public.suggested_friends(integer,integer) from public,anon;
grant execute on function public.set_friend_discovery(boolean),public.dismiss_friend_suggestion(uuid),public.suggested_friends(integer,integer) to authenticated;
commit;
