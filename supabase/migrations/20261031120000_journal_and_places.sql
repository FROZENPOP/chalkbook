-- Phase 0 of REBUILD_PLAN.md: the server-backed journal, shared gyms and routes, and one-way follows.
-- Friendships are copied into follows at the Phase 3 cutover, not here, so the two cannot drift apart before then.
-- The app does not read these tables yet. Health data never enters them.
begin;
create table public.gyms (
  id uuid primary key default gen_random_uuid(),
  name text not null check(length(trim(name)) between 1 and 120),
  address text not null default '' check(length(address) <= 300),
  latitude double precision check(latitude between -90 and 90),
  longitude double precision check(longitude between -180 and 180),
  apple_place_id text unique check(length(apple_place_id) <= 200),
  grade_scale text not null default '' check(length(grade_scale) <= 40),
  colour_guide text not null default '' check(length(colour_guide) <= 2000),
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);
create table public.walls (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  name text not null check(length(trim(name)) between 1 and 80),
  sort integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  unique(gym_id,id)
);
create table public.routes (
  id uuid primary key default gen_random_uuid(),
  gym_id uuid not null references public.gyms(id) on delete cascade,
  wall_id uuid,
  colour text not null default '' check(length(colour) <= 40),
  grade_kind text not null default 'exact' check(grade_kind in ('exact','range','color','colorRange','unknown')),
  grade text not null default '' check(length(grade) <= 20),
  grade_upper text not null default '' check(length(grade_upper) <= 20),
  set_on date check(set_on between date '2000-01-01' and date '2100-01-01'),
  status text not null default 'active' check(status in ('active','retired')),
  created_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now(),
  foreign key(gym_id,wall_id) references public.walls(gym_id,id) -- A wall must belong to the route's gym.
);
create index routes_gym on public.routes(gym_id);
create table public.personal_routes (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null default '' check(length(name) <= 120),
  grade_scale text not null default '' check(length(grade_scale) <= 40),
  colour text not null default '' check(length(colour) <= 40),
  grade_kind text not null default 'exact' check(grade_kind in ('exact','range','color','colorRange','unknown')),
  grade text not null default '' check(length(grade) <= 20),
  grade_upper text not null default '' check(length(grade_upper) <= 20),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index personal_routes_owner on public.personal_routes(owner_id);
create table public.sessions (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  gym_id uuid references public.gyms(id) on delete set null,
  started_at timestamptz not null check(started_at between timestamptz '2000-01-01' and timestamptz '2100-01-01'),
  ended_at timestamptz,
  tz text not null check(tz ~ '^[A-Za-z0-9_+/-]{1,64}$'),
  visibility text not null default 'followers' check(visibility in ('private','followers','public')),
  caption text not null default '' check(length(caption) <= 1000),
  manual_attempts integer check(manual_attempts between 0 and 100000),
  manual_sends integer check(manual_sends between 0 and 100000),
  hide_gym boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check(ended_at is null or ended_at >= started_at),
  check(manual_attempts is null or manual_sends is null or manual_sends <= manual_attempts)
);
create index sessions_owner on public.sessions(owner_id, updated_at);
create table public.attempts (
  id uuid primary key,
  session_id uuid not null references public.sessions(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  route_id uuid references public.routes(id) on delete set null,
  personal_route_id uuid references public.personal_routes(id) on delete set null,
  seq integer not null check(seq between 0 and 100000),
  sent boolean not null,
  at timestamptz not null check(at between timestamptz '2000-01-01' and timestamptz '2100-01-01'),
  precision text not null default 'exact' check(precision in ('exact','day')),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  check(num_nonnulls(route_id, personal_route_id) <= 1)
);
create index attempts_session on public.attempts(session_id);
create index attempts_owner on public.attempts(owner_id, updated_at);
create index attempts_route on public.attempts(route_id);
create table public.route_notes (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  route_id uuid not null references public.routes(id) on delete cascade,
  body text not null default '' check(length(body) <= 5000),
  pinned boolean not null default false,
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index route_notes_owner on public.route_notes(owner_id, updated_at);
create table public.media (
  id uuid primary key,
  owner_id uuid not null references auth.users(id) on delete cascade,
  session_id uuid references public.sessions(id) on delete cascade,
  route_id uuid references public.routes(id) on delete set null,
  kind text not null check(kind in ('photo','video')),
  storage_path text not null check(length(storage_path) between 1 and 500 and storage_path !~ '(^|/)\.\.?(/|$)'),
  check(split_part(storage_path,'/',1) = owner_id::text), -- Storage access can key off this row, so a row may only name its owner's files.
  visibility text not null default 'session' check(visibility in ('private','session')), -- 'session' follows the session's audience.
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create index media_session on public.media(session_id);
create table public.kudos (
  session_id uuid not null references public.sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(session_id,user_id)
);
create table public.comments (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  body text not null check(length(trim(body)) between 1 and 1000),
  created_at timestamptz not null default now()
);
create index comments_session on public.comments(session_id);
create table public.follows (
  follower_id uuid not null references public.climber_profiles(id) on delete cascade,
  followee_id uuid not null references public.climber_profiles(id) on delete cascade,
  status text not null default 'pending' check(status in ('pending','accepted')),
  created_at timestamptz not null default now(),
  primary key(follower_id,followee_id), check(follower_id <> followee_id)
);
create index follows_followee on public.follows(followee_id);

create function social_private.following(owner uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.follows where follower_id=auth.uid() and followee_id=owner and status='accepted')
 and not social_private.blocked(owner)
$$;
-- Sessions that hide their gym stay invisible to others until the Phase 3 feed strips the gym server-side.
create function social_private.visible_session(owner uuid, audience text, hidden_gym boolean, deleted timestamptz) returns boolean
language sql stable security definer set search_path='' as $$
 select owner=auth.uid() or (deleted is null and not hidden_gym and not social_private.blocked(owner) and
 ((audience in ('followers','public') and social_private.following(owner)) or
 (audience='public' and exists(select 1 from public.climber_profiles where id=owner and not is_private))))
$$;
create function social_private.session_visible(session uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select coalesce((select social_private.visible_session(owner_id,visibility,hide_gym,deleted_at) from public.sessions where id=session),false)
$$;
create function social_private.shared_by_other(session uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.shared_sessions where source_session_id=session and owner_id<>auth.uid())
$$;
create function social_private.owns_session(session uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.sessions where id=session and owner_id=auth.uid())
$$;
create function social_private.owns_personal_route(route uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select route is null or exists(select 1 from public.personal_routes where id=route and owner_id=auth.uid())
$$;
-- Sync cursors read updated_at, so the server sets it and clients cannot backdate or future-date rows.
create function social_private.touch_updated_at() returns trigger
language plpgsql set search_path='' as $$ begin new.updated_at=now(); return new; end $$;
create trigger touch before insert or update on public.routes for each row execute function social_private.touch_updated_at();
create trigger touch before insert or update on public.personal_routes for each row execute function social_private.touch_updated_at();
create trigger touch before insert or update on public.sessions for each row execute function social_private.touch_updated_at();
create trigger touch before insert or update on public.attempts for each row execute function social_private.touch_updated_at();
create trigger touch before insert or update on public.route_notes for each row execute function social_private.touch_updated_at();
create trigger touch before insert or update on public.media for each row execute function social_private.touch_updated_at();
create function social_private.unfollow_on_block() returns trigger
language plpgsql security definer set search_path='' as $$
begin
 delete from public.follows where (follower_id=new.owner_id and followee_id=new.target_id) or (follower_id=new.target_id and followee_id=new.owner_id);
 return new;
end $$;
create trigger unfollow after insert on public.climber_blocks for each row execute function social_private.unfollow_on_block();

alter table public.gyms enable row level security;
alter table public.walls enable row level security;
alter table public.routes enable row level security;
alter table public.personal_routes enable row level security;
alter table public.sessions enable row level security;
alter table public.attempts enable row level security;
alter table public.route_notes enable row level security;
alter table public.media enable row level security;
alter table public.kudos enable row level security;
alter table public.comments enable row level security;
alter table public.follows enable row level security;
-- Shared places are crowd-sourced: anyone signed in can read and add; only the creator edits.
create policy gyms_read on public.gyms for select to authenticated using(true);
create policy gyms_add on public.gyms for insert to authenticated with check(created_by=(select auth.uid()));
create policy gyms_edit on public.gyms for update to authenticated using(created_by=(select auth.uid())) with check(created_by=(select auth.uid()));
create policy walls_read on public.walls for select to authenticated using(true);
create policy walls_add on public.walls for insert to authenticated with check(created_by=(select auth.uid()));
create policy walls_edit on public.walls for update to authenticated using(created_by=(select auth.uid())) with check(created_by=(select auth.uid()));
create policy routes_read on public.routes for select to authenticated using(true);
create policy routes_add on public.routes for insert to authenticated with check(created_by=(select auth.uid()));
create policy routes_edit on public.routes for update to authenticated using(created_by=(select auth.uid())) with check(created_by=(select auth.uid()));
-- Journal rows are written by their owner as idempotent upserts from the sync outbox; deletes are tombstones.
create policy personal_routes_owner on public.personal_routes for all to authenticated
 using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
create policy route_notes_owner on public.route_notes for all to authenticated
 using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
create policy sessions_read on public.sessions for select to authenticated using(social_private.visible_session(owner_id,visibility,hide_gym,deleted_at));
-- A friend can see a shared post's source_session_id, so they must not be able to claim that id first.
create policy sessions_add on public.sessions for insert to authenticated with check(owner_id=(select auth.uid()) and not social_private.shared_by_other(id));
create policy sessions_edit on public.sessions for update to authenticated using(owner_id=(select auth.uid())) with check(owner_id=(select auth.uid()));
create policy attempts_read on public.attempts for select to authenticated
 using(owner_id=(select auth.uid()) or (deleted_at is null and social_private.session_visible(session_id)));
create policy attempts_add on public.attempts for insert to authenticated
 with check(owner_id=(select auth.uid()) and social_private.owns_session(session_id) and social_private.owns_personal_route(personal_route_id));
create policy attempts_edit on public.attempts for update to authenticated using(owner_id=(select auth.uid()))
 with check(owner_id=(select auth.uid()) and social_private.owns_session(session_id) and social_private.owns_personal_route(personal_route_id));
create policy media_read on public.media for select to authenticated
 using(owner_id=(select auth.uid()) or (visibility='session' and deleted_at is null and social_private.session_visible(session_id)));
create policy media_add on public.media for insert to authenticated
 with check(owner_id=(select auth.uid()) and (session_id is null or social_private.owns_session(session_id)));
create policy media_edit on public.media for update to authenticated using(owner_id=(select auth.uid()))
 with check(owner_id=(select auth.uid()) and (session_id is null or social_private.owns_session(session_id)));
create policy kudos_read on public.kudos for select to authenticated
 using(social_private.session_visible(session_id) and not social_private.blocked(user_id));
create policy kudos_add on public.kudos for insert to authenticated
 with check(user_id=(select auth.uid()) and social_private.session_visible(session_id));
create policy kudos_remove on public.kudos for delete to authenticated using(user_id=(select auth.uid()));
create policy comments_read on public.comments for select to authenticated
 using(social_private.session_visible(session_id) and not social_private.blocked(user_id));
create policy comments_add on public.comments for insert to authenticated
 with check(user_id=(select auth.uid()) and social_private.session_visible(session_id));
-- Authors remove their comments; session owners moderate their own posts.
create policy comments_remove on public.comments for delete to authenticated
 using(user_id=(select auth.uid()) or social_private.owns_session(session_id));
create policy follows_read on public.follows for select to authenticated using
 ((follower_id=(select auth.uid()) or followee_id=(select auth.uid()))
 and not social_private.blocked(case when follower_id=(select auth.uid()) then followee_id else follower_id end));

-- Follows cross two accounts, so they go through one RPC: nobody approves their own request.
create function social_private.follow_action(target uuid, action text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null or target=auth.uid() or social_private.blocked(target) then raise exception 'Unavailable'; end if;
 if action='follow' then
   insert into public.follows(follower_id,followee_id,status)
   select auth.uid(),id,case when is_private then 'pending' else 'accepted' end from public.climber_profiles where id=target
   on conflict do nothing;
 elsif action='approve' then
   update public.follows set status='accepted' where follower_id=target and followee_id=auth.uid() and status='pending';
 elsif action='decline' then
   delete from public.follows where follower_id=target and followee_id=auth.uid();
 elsif action='unfollow' then
   delete from public.follows where follower_id=auth.uid() and followee_id=target;
 else raise exception 'Unknown action'; end if;
end $$;
create function public.follow_action(target uuid, action text) returns void
language sql security invoker set search_path='' as $$ select social_private.follow_action($1,$2); $$;

revoke all on function social_private.following(uuid), social_private.visible_session(uuid,text,boolean,timestamptz),
 social_private.session_visible(uuid), social_private.owns_session(uuid), social_private.owns_personal_route(uuid),
 social_private.touch_updated_at(), social_private.unfollow_on_block(), social_private.follow_action(uuid,text),
 public.follow_action(uuid,text) from public,anon;
grant execute on function social_private.following(uuid), social_private.visible_session(uuid,text,boolean,timestamptz),
 social_private.session_visible(uuid), social_private.owns_session(uuid), social_private.owns_personal_route(uuid),
 social_private.follow_action(uuid,text), public.follow_action(uuid,text) to authenticated;
revoke all on public.gyms, public.walls, public.routes, public.personal_routes, public.sessions, public.attempts,
 public.route_notes, public.media, public.kudos, public.comments, public.follows from public,anon,authenticated;
grant select on public.gyms, public.walls, public.routes, public.personal_routes, public.sessions, public.attempts,
 public.route_notes, public.media, public.kudos, public.comments, public.follows to authenticated;
grant insert, update on public.gyms, public.walls, public.routes, public.personal_routes, public.sessions, public.attempts,
 public.route_notes, public.media to authenticated;
grant insert, delete on public.kudos, public.comments to authenticated;
revoke all on function social_private.shared_by_other(uuid) from public,anon;
grant execute on function social_private.shared_by_other(uuid) to authenticated;

-- Places are shared and only their creator edits them, so cap how many one account can add.
create function social_private.limit_places() returns trigger
language plpgsql security definer set search_path='' as $$
declare made integer;
begin
 if new.created_by is null then return new; end if;
 if tg_table_name='gyms' then select count(*) into made from public.gyms where created_by=new.created_by;
  if made>=200 then raise exception 'Gym limit reached'; end if;
 elsif tg_table_name='walls' then select count(*) into made from public.walls where created_by=new.created_by;
  if made>=2000 then raise exception 'Wall limit reached'; end if;
 else select count(*) into made from public.routes where created_by=new.created_by;
  if made>=20000 then raise exception 'Route limit reached'; end if;
 end if;
 return new;
end $$;
revoke all on function social_private.limit_places() from public,anon,authenticated;
create trigger limit_gyms before insert on public.gyms for each row execute function social_private.limit_places();
create trigger limit_walls before insert on public.walls for each row execute function social_private.limit_places();
create trigger limit_routes before insert on public.routes for each row execute function social_private.limit_places();
commit;
