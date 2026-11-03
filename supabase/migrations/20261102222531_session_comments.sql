-- Comments on shared sessions. Anyone who can see a post can comment; writes go through
-- narrow RPCs, and reads follow the post's audience and hide blocked climbers.
begin;

create table public.session_comments (
 id uuid primary key default gen_random_uuid(),
 entry_id uuid not null references public.shared_sessions(id) on delete cascade,
 user_id uuid not null references public.climber_profiles(id) on delete cascade,
 body text not null check(char_length(body) between 1 and 500),
 -- Whole seconds so the client can decode the timestamp as plain ISO 8601.
 created_at timestamptz not null default date_trunc('second',now())
);
create index session_comments_entry_idx on public.session_comments(entry_id,created_at);
create index session_comments_user_idx on public.session_comments(user_id);
alter table public.session_comments enable row level security;
revoke all on public.session_comments from anon,authenticated;
grant select on public.session_comments to authenticated;
create policy comments_read on public.session_comments for select to authenticated using
 (not social_private.blocked(user_id) and exists(select 1 from public.shared_sessions s where s.id=entry_id));

create function social_private.add_session_comment(entry uuid,message text) returns public.session_comments
language plpgsql security definer set search_path='' as $$
declare
 saved public.session_comments;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if not exists(select 1 from public.shared_sessions s where s.id=entry
 and social_private.visible_entry(s.owner_id,s.visibility)) then raise exception 'Entry unavailable'; end if;
 insert into public.session_comments(entry_id,user_id,body) values(entry,auth.uid(),trim(message)) returning * into saved;
 return saved;
end $$;
revoke all on function social_private.add_session_comment(uuid,text) from public,anon;
grant execute on function social_private.add_session_comment(uuid,text) to authenticated;
create function public.add_session_comment(entry uuid,message text) returns public.session_comments
language sql security invoker set search_path='' as $$
 select social_private.add_session_comment($1,$2);
$$;
revoke all on function public.add_session_comment(uuid,text) from public,anon;
grant execute on function public.add_session_comment(uuid,text) to authenticated;

-- Authors can remove their own comments; post owners can remove any comment on their post.
create function social_private.delete_session_comment(comment uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 delete from public.session_comments c where c.id=comment and (c.user_id=auth.uid() or exists(
 select 1 from public.shared_sessions s where s.id=c.entry_id and s.owner_id=auth.uid()));
 if not found then raise exception 'Comment unavailable'; end if;
end $$;
revoke all on function social_private.delete_session_comment(uuid) from public,anon;
grant execute on function social_private.delete_session_comment(uuid) to authenticated;
create function public.delete_session_comment(comment uuid) returns void
language sql security invoker set search_path='' as $$
 select social_private.delete_session_comment($1);
$$;
revoke all on function public.delete_session_comment(uuid) from public,anon;
grant execute on function public.delete_session_comment(uuid) to authenticated;

commit;
