-- Reviewed session snapshots only. Private journals, notes, media and Health data never enter these tables.
begin;
create table public.climber_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[a-z0-9_]{3,24}$'),
  display_name text not null check (length(trim(display_name)) between 1 and 60),
  is_private boolean not null default true,
  updated_at timestamptz not null default now()
);
create table public.friendships (
  requester uuid not null references public.climber_profiles(id) on delete cascade,
  recipient uuid not null references public.climber_profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  primary key(requester,recipient), check(requester <> recipient)
);
create unique index one_friendship_per_pair on public.friendships(least(requester,recipient), greatest(requester,recipient));
create index friendships_recipient on public.friendships(recipient);
create table public.climber_blocks (
  owner_id uuid not null references public.climber_profiles(id) on delete cascade,
  target_id uuid not null references public.climber_profiles(id) on delete cascade,
  primary key(owner_id,target_id), check(owner_id <> target_id)
);
create table public.shared_sessions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.climber_profiles(id) on delete cascade,
  source_session_id uuid not null,
  visibility text not null default 'private' check(visibility in ('private','friends','public')),
  caption text not null default '' check(length(caption) <= 1000),
  session_day text not null check(session_day ~ '^\d{4}-\d{2}-\d{2}$'),
  attempts integer check(attempts between 0 and 100000),
  sends integer check(sends between 0 and 100000),
  duration_minutes integer check(duration_minutes between 0 and 10080),
  completeness text not null check(length(completeness) <= 200),
  updated_at timestamptz not null default now(),
  unique(owner_id,source_session_id), check(attempts is null or sends is null or sends <= attempts)
);
create index shared_sessions_owner on public.shared_sessions(owner_id);
create table public.social_reports (
  id uuid primary key default gen_random_uuid(),
  reporter uuid not null references auth.users(id) on delete cascade,
  target_id uuid not null references public.climber_profiles(id) on delete cascade,
  reason text not null check(length(trim(reason)) between 1 and 1000),
  created_at timestamptz not null default now()
);

create schema if not exists social_private;
revoke all on schema social_private from public;
grant usage on schema social_private to authenticated;
create function social_private.blocked(other uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.climber_blocks where
 (owner_id=auth.uid() and target_id=other) or (target_id=auth.uid() and owner_id=other))
$$;
create function social_private.friends(other uuid) returns boolean
language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.friendships where status='accepted' and
 ((requester=auth.uid() and recipient=other) or (recipient=auth.uid() and requester=other)))
 and not social_private.blocked(other)
$$;
create function social_private.visible_entry(owner uuid, audience text) returns boolean
language sql stable security definer set search_path = '' as $$
 select owner=auth.uid() or (not social_private.blocked(owner) and
 ((audience in ('friends','public') and social_private.friends(owner)) or
 (audience='public' and exists(select 1 from public.climber_profiles where id=owner and not is_private))))
$$;
alter table public.climber_profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.climber_blocks enable row level security;
alter table public.shared_sessions enable row level security;
alter table public.social_reports enable row level security;
create policy profiles_read on public.climber_profiles for select to authenticated using(not social_private.blocked(id));
create policy friendships_read on public.friendships for select to authenticated using
 ((requester=auth.uid() or recipient=auth.uid()) and not social_private.blocked(case when requester=auth.uid() then recipient else requester end));
create policy blocks_read on public.climber_blocks for select to authenticated using(owner_id=auth.uid());
create policy sessions_read on public.shared_sessions for select to authenticated using(social_private.visible_entry(owner_id,visibility));
-- Mutations go through narrow RPCs; no client can approve their own request or forge another owner.
revoke all on public.climber_profiles, public.friendships, public.climber_blocks, public.shared_sessions, public.social_reports from anon, authenticated;
grant select on public.climber_profiles, public.friendships, public.climber_blocks, public.shared_sessions to authenticated;

create function public.save_social_profile(username text, display_name text, is_private boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 insert into public.climber_profiles values(auth.uid(),lower(trim(username)),trim(display_name),is_private,now())
 on conflict(id) do update set username=excluded.username,display_name=excluded.display_name,is_private=excluded.is_private,updated_at=now();
end $$;
create function public.friend_action(target uuid, action text) returns void
language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null or target=auth.uid() or social_private.blocked(target) then raise exception 'Unavailable'; end if;
 if action='request' then
   insert into public.friendships(requester,recipient) values(auth.uid(),target) on conflict do nothing;
 elsif action='accept' then
   update public.friendships set status='accepted' where requester=target and recipient=auth.uid() and status='pending';
 elsif action in ('remove','decline','cancel') then
   delete from public.friendships where (requester=auth.uid() and recipient=target) or (recipient=auth.uid() and requester=target);
 else raise exception 'Unknown action'; end if;
end $$;
create function public.save_shared_session(source_session_id uuid, visibility text, caption text, session_day text,
 attempts integer, sends integer, duration_minutes integer, completeness text) returns void
language plpgsql security definer set search_path = '' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 insert into public.shared_sessions(owner_id,source_session_id,visibility,caption,session_day,attempts,sends,duration_minutes,completeness)
 values(auth.uid(),source_session_id,visibility,caption,session_day,attempts,sends,duration_minutes,completeness)
 on conflict on constraint shared_sessions_owner_id_source_session_id_key do update set visibility=excluded.visibility,caption=excluded.caption,
 session_day=excluded.session_day,attempts=excluded.attempts,sends=excluded.sends,duration_minutes=excluded.duration_minutes,
 completeness=excluded.completeness,updated_at=now();
end $$;
create function public.remove_shared_session(source_id uuid) returns void
language sql security definer set search_path = '' as $$
 delete from public.shared_sessions where owner_id=auth.uid() and source_session_id=source_id
$$;
create function public.block_climber(target uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
 insert into public.climber_blocks values(auth.uid(),target) on conflict do nothing;
 delete from public.friendships where (requester=auth.uid() and recipient=target) or (recipient=auth.uid() and requester=target);
end $$;
create function public.unblock_climber(target uuid) returns void
language sql security definer set search_path = '' as $$
 delete from public.climber_blocks where owner_id=auth.uid() and target_id=target
$$;
create function public.report_climber(target uuid, reason text) returns void
language sql security definer set search_path = '' as $$
 insert into public.social_reports(reporter,target_id,reason) values(auth.uid(),target,reason)
$$;
create function public.delete_social_profile() returns void
language sql security definer set search_path = '' as $$
 delete from public.climber_profiles where id=auth.uid()
$$;
revoke all on all functions in schema social_private from public, anon;
grant execute on all functions in schema social_private to authenticated;
revoke all on function public.save_social_profile(text,text,boolean), public.friend_action(uuid,text),
 public.save_shared_session(uuid,text,text,text,integer,integer,integer,text), public.remove_shared_session(uuid),
 public.block_climber(uuid), public.unblock_climber(uuid), public.report_climber(uuid,text), public.delete_social_profile() from public,anon;
grant execute on function public.save_social_profile(text,text,boolean), public.friend_action(uuid,text),
 public.save_shared_session(uuid,text,text,text,integer,integer,integer,text), public.remove_shared_session(uuid),
 public.block_climber(uuid), public.unblock_climber(uuid), public.report_climber(uuid,text), public.delete_social_profile() to authenticated;
commit;
