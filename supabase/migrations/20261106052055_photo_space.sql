-- Keep Friends photos under a space budget so the free database never fills up.
-- When a new post's photos don't fit, the poster's own oldest post photos are removed first;
-- if none are left, the post is saved without photos. Returns 'saved', 'trimmed' or 'no_space'.
begin;

-- 300 MB of the free plan's 500 MB database, leaving room for everything else. Tests override it.
create function social_private.photo_space_budget() returns bigint language sql stable set search_path='' as $$ select 300000000::bigint $$;
revoke all on function social_private.photo_space_budget() from public,anon,authenticated;

create function social_private.route_photo_bytes() returns bigint language sql stable set search_path='' as $$
 select coalesce(sum(octet_length(p.original_base64)+coalesce(octet_length(p.highlighted_base64),0)),0)::bigint from public.shared_route_photos p
$$;
revoke all on function social_private.route_photo_bytes() from public,anon,authenticated;

drop function public.save_shared_session_with_photos(uuid,text,text,text,integer,integer,integer,text,jsonb);
drop function social_private.save_shared_session_with_photos(uuid,text,text,text,integer,integer,integer,text,jsonb);

create function social_private.save_shared_session_with_photos(source_session_id uuid, visibility text, caption text, session_day text,
 attempts integer, sends integer, duration_minutes integer, completeness text, photos jsonb) returns text
language plpgsql security definer set search_path='' as $$
declare entry uuid; photo jsonb; ordinal integer:=0; incoming bigint:=0; oldest uuid; outcome text:='saved';
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if photos is null or jsonb_typeof(photos)<>'array' or jsonb_array_length(photos)>3 then raise exception 'Invalid photo selection'; end if;
 for photo in select value from jsonb_array_elements(photos) loop
  if jsonb_typeof(photo)<>'object' or not(photo ? 'id' and photo ? 'original_base64') or
     exists(select 1 from jsonb_object_keys(photo) k where k not in ('id','original_base64','highlighted_base64')) then raise exception 'Invalid photo fields'; end if;
  incoming:=incoming+octet_length(photo->>'original_base64')+coalesce(octet_length(photo->>'highlighted_base64'),0);
 end loop;
 perform social_private.save_shared_session($1,$2,$3,$4,$5,$6,$7,$8);
 select s.id into strict entry from public.shared_sessions s where s.owner_id=auth.uid() and s.source_session_id=$1;
 delete from public.shared_route_photos p where p.entry_id=entry;

 -- shortcut: expiry runs whenever anyone saves photos, not on a schedule. Storage only grows here, so this bounds it; move to pg_cron if photos must vanish on the dot.
 with gone as (delete from public.shared_route_photos p where p.created_at < now() - interval '30 days' returning p.entry_id)
 update public.shared_sessions s set route_photo_count=0 where s.id in (select g.entry_id from gone g);

 with extra as (
  select p.entry_id from public.shared_route_photos p join public.shared_sessions s on s.id=p.entry_id
  where s.owner_id=auth.uid() and p.entry_id<>entry group by p.entry_id order by max(p.created_at) desc, p.entry_id offset 9
 ), gone as (delete from public.shared_route_photos p where p.entry_id in (select e.entry_id from extra e) returning p.entry_id)
 update public.shared_sessions s set route_photo_count=0 where s.id in (select g.entry_id from gone g);

 -- shortcut: concurrent saves can each see the same free space and overshoot the budget a little; it is set well below the real limit for that.
 while incoming>0 and social_private.route_photo_bytes()+incoming > social_private.photo_space_budget() loop
  select p.entry_id into oldest from public.shared_route_photos p join public.shared_sessions s on s.id=p.entry_id
  where s.owner_id=auth.uid() and p.entry_id<>entry group by p.entry_id order by max(p.created_at), p.entry_id limit 1;
  if oldest is null then outcome:='no_space'; exit; end if;
  delete from public.shared_route_photos p where p.entry_id=oldest;
  update public.shared_sessions s set route_photo_count=0 where s.id=oldest;
  outcome:='trimmed'; oldest:=null;
 end loop;

 if outcome<>'no_space' then
  for photo in select value from jsonb_array_elements(photos) loop
   insert into public.shared_route_photos(id,entry_id,position,original_base64,highlighted_base64)
    values((photo->>'id')::uuid,entry,ordinal,photo->>'original_base64',photo->>'highlighted_base64');
   ordinal:=ordinal+1;
  end loop;
 end if;
 update public.shared_sessions s set route_photo_count=ordinal where s.id=entry and s.owner_id=auth.uid();
 return outcome;
end;
$$;
revoke all on function social_private.save_shared_session_with_photos(uuid,text,text,text,integer,integer,integer,text,jsonb) from public,anon;
grant execute on function social_private.save_shared_session_with_photos(uuid,text,text,text,integer,integer,integer,text,jsonb) to authenticated;

create function public.save_shared_session_with_photos(source_session_id uuid, visibility text, caption text, session_day text,
 attempts integer, sends integer, duration_minutes integer, completeness text, photos jsonb) returns text
language sql security invoker set search_path='' as $$
 select social_private.save_shared_session_with_photos($1,$2,$3,$4,$5,$6,$7,$8,$9);
$$;
revoke all on function public.save_shared_session_with_photos(uuid,text,text,text,integer,integer,integer,text,jsonb) from public,anon;
grant execute on function public.save_shared_session_with_photos(uuid,text,text,text,integer,integer,integer,text,jsonb) to authenticated;
commit;
