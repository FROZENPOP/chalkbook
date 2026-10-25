begin;
-- Kept separate from discoverable handles: private accounts' bio/photo require friendship.
create table public.climber_profile_details (
 id uuid primary key references public.climber_profiles(id) on delete cascade,
 bio text not null default '' check(length(bio)<=240),
 avatar_base64 text check(length(avatar_base64)<=90000 and octet_length(decode(avatar_base64,'base64'))<=65536),
 updated_at timestamptz not null default now()
);
alter table public.climber_profile_details enable row level security;
revoke all on public.climber_profile_details from anon,authenticated;
grant select on public.climber_profile_details to authenticated;
create policy details_read on public.climber_profile_details for select to authenticated using
 (id=auth.uid() or (not social_private.blocked(id) and
 (social_private.friends(id) or exists(select 1 from public.climber_profiles p where p.id=climber_profile_details.id and not p.is_private))));

create function public.save_social_profile_v2(username text,display_name text,is_private boolean,bio text,avatar_base64 text) returns void
language plpgsql security definer set search_path='' as $$
begin
 perform public.save_social_profile(username,display_name,is_private);
 insert into public.climber_profile_details values(auth.uid(),trim(bio),avatar_base64,now())
 on conflict(id) do update set bio=excluded.bio,avatar_base64=excluded.avatar_base64,updated_at=now();
end $$;

create function public.search_climbers(search_text text) returns setof public.climber_profiles
language sql stable security invoker set search_path='' as $$
 with term as (select lower(trim(search_text)) as q),
 pattern as (select q,replace(replace(replace(q,'\','\\'),'%','\%'),'_','\_') as literal from term)
 select p.* from public.climber_profiles p cross join pattern t
 where length(t.q) between 2 and 60 and p.id<>auth.uid() and
 (p.username ilike t.literal||'%' or p.display_name ilike '%'||t.literal||'%')
 order by case when p.username=t.q then 0 when lower(p.display_name)=t.q then 1
 when p.username ilike t.literal||'%' then 2 else 3 end,p.username limit 30
$$;

create table public.session_reactions (
 entry_id uuid not null references public.shared_sessions(id) on delete cascade,
 user_id uuid not null references public.climber_profiles(id) on delete cascade,
 kind text not null check(kind in ('clap','fire','strong')),
 primary key(entry_id,user_id)
);
alter table public.session_reactions enable row level security;
revoke all on public.session_reactions from anon,authenticated;
grant select on public.session_reactions to authenticated;
create policy reactions_read on public.session_reactions for select to authenticated using
 (not social_private.blocked(user_id) and exists(select 1 from public.shared_sessions s where s.id=entry_id));
create function public.set_session_reaction(entry uuid,reaction text) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not exists(select 1 from public.shared_sessions s where s.id=entry and s.owner_id<>auth.uid()
 and social_private.visible_entry(s.owner_id,s.visibility)) then raise exception 'Entry unavailable'; end if;
 if reaction is null then delete from public.session_reactions where entry_id=entry and user_id=auth.uid();
 else insert into public.session_reactions values(entry,auth.uid(),reaction)
 on conflict(entry_id,user_id) do update set kind=excluded.kind; end if;
end $$;
create function public.reaction_summary(entries uuid[]) returns table(entry_id uuid,kind text,total bigint,mine boolean)
language plpgsql stable security invoker set search_path='' as $$
begin
 if coalesce(cardinality(entries),0) not between 1 and 200 or exists(
 select 1 from unnest(entries) requested where not exists(select 1 from public.shared_sessions s where s.id=requested))
 then raise exception 'Entry unavailable'; end if;
 return query select r.entry_id,r.kind,count(*),bool_or(r.user_id=auth.uid()) from public.session_reactions r
 where r.entry_id=any(entries) group by r.entry_id,r.kind;
end
$$;
revoke all on function public.save_social_profile_v2(text,text,boolean,text,text),public.search_climbers(text),
 public.set_session_reaction(uuid,text),public.reaction_summary(uuid[]) from public,anon;
grant execute on function public.save_social_profile_v2(text,text,boolean,text,text),public.search_climbers(text),
 public.set_session_reaction(uuid,text),public.reaction_summary(uuid[]) to authenticated;
commit;
