-- Abuse limits found in the pre-publication security review:
-- 1. Each account gets a 5 MB Friends photo quota, so a few accounts can't use up the shared 300 MB budget.
-- 2. Report alerts ping the moderator at most once every 10 minutes, however many accounts file reports.
begin;

-- 5 MB is several full posts (3 photos with highlights, each under 128 KB). Tests override it.
create function social_private.account_photo_budget() returns bigint language sql stable set search_path='' as $$ select 5000000::bigint $$;
revoke all on function social_private.account_photo_budget() from public,anon,authenticated;

create or replace function social_private.save_shared_session_with_photos(source_session_id uuid, visibility text, caption text, session_day text,
 attempts integer, sends integer, duration_minutes integer, completeness text, photos jsonb) returns text
language plpgsql security definer set search_path='' as $$
declare entry uuid; photo jsonb; ordinal integer:=0; incoming bigint:=0; oldest uuid; outcome text:='saved';
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if photos is null or jsonb_typeof(photos)<>'array' or jsonb_array_length(photos)>3 then raise exception 'Invalid photo selection'; end if;
 for photo in select value from jsonb_array_elements(photos) loop
  if jsonb_typeof(photo)<>'object' or not(photo ? 'id' and photo ? 'original_base64') or
     exists(select 1 from jsonb_object_keys(photo) k where k not in ('id','original_base64','highlighted_base64')) then raise exception 'Invalid photo fields'; end if;
  -- The same rules the insert enforces, checked here because the no_space path never inserts.
  if coalesce(photo->>'id','') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' or
     not coalesce(social_private.valid_route_jpeg(photo->>'original_base64'),false) or
     not coalesce(social_private.valid_route_jpeg(photo->>'highlighted_base64'),photo->>'highlighted_base64' is null) then raise exception 'Invalid photo data'; end if;
  incoming:=incoming+octet_length(photo->>'original_base64')+coalesce(octet_length(photo->>'highlighted_base64'),0);
 end loop;
 perform social_private.save_shared_session($1,$2,$3,$4,$5,$6,$7,$8);
 select s.id into strict entry from public.shared_sessions s where s.owner_id=auth.uid() and s.source_session_id=$1;
 delete from public.shared_route_photos p where p.entry_id=entry;

 -- shortcut: expiry runs whenever anyone saves photos, not on a schedule. Storage only grows here, so this bounds it; move to pg_cron if photos must vanish on the dot.
 with gone as (delete from public.shared_route_photos p where p.created_at < now() - interval '30 days' returning p.entry_id)
 update public.shared_sessions s set route_photo_count=0 where s.id in (select g.entry_id from gone g);

 -- Trim only if removing all of the poster's other photos would make room; otherwise keep them.
 if incoming>0 and social_private.route_photo_bytes()+incoming-(
   select coalesce(sum(octet_length(p.original_base64)+coalesce(octet_length(p.highlighted_base64),0)),0) from public.shared_route_photos p
   join public.shared_sessions s on s.id=p.entry_id where s.owner_id=auth.uid() and p.entry_id<>entry) > social_private.photo_space_budget() then
  outcome:='no_space';
 elsif incoming>0 then
  -- The 10-post cap runs only when this save stores photos.
  with extra as (
   select p.entry_id from public.shared_route_photos p join public.shared_sessions s on s.id=p.entry_id
   where s.owner_id=auth.uid() and p.entry_id<>entry group by p.entry_id order by max(p.created_at) desc, p.entry_id offset 9
  ), gone as (delete from public.shared_route_photos p where p.entry_id in (select e.entry_id from extra e) returning p.entry_id)
  update public.shared_sessions s set route_photo_count=0 where s.id in (select g.entry_id from gone g);
  -- Each account also gets its own byte quota, so a handful of accounts can't fill the shared budget.
  loop
   exit when (select coalesce(sum(octet_length(p.original_base64)+coalesce(octet_length(p.highlighted_base64),0)),0) from public.shared_route_photos p
    join public.shared_sessions s on s.id=p.entry_id where s.owner_id=auth.uid() and p.entry_id<>entry)+incoming <= social_private.account_photo_budget();
   select p.entry_id into oldest from public.shared_route_photos p join public.shared_sessions s on s.id=p.entry_id
   where s.owner_id=auth.uid() and p.entry_id<>entry group by p.entry_id order by max(p.created_at), p.entry_id limit 1;
   exit when oldest is null;
   delete from public.shared_route_photos p where p.entry_id=oldest;
   update public.shared_sessions s set route_photo_count=0 where s.id=oldest;
   outcome:='trimmed'; oldest:=null;
  end loop;
 end if;

 -- shortcut: concurrent saves can each see the same free space and overshoot the budget a little; it is set well below the real limit for that.
 while outcome<>'no_space' and incoming>0 and social_private.route_photo_bytes()+incoming > social_private.photo_space_budget() loop
  select p.entry_id into oldest from public.shared_route_photos p join public.shared_sessions s on s.id=p.entry_id
  where s.owner_id=auth.uid() and p.entry_id<>entry group by p.entry_id order by max(p.created_at), p.entry_id limit 1;
  -- Only a concurrent save can get here; photos were already trimmed, so store these and overshoot slightly.
  exit when oldest is null;
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
revoke all on function public.save_shared_session_with_photos(uuid,text,text,text,integer,integer,integer,text,jsonb) from public,anon;
grant execute on function public.save_shared_session_with_photos(uuid,text,text,text,integer,integer,integer,text,jsonb) to authenticated;

-- Every report is still claimed once, but only the first in a 10-minute window pings; the queue holds them all.
create or replace function social_private.claim_report_alert() returns boolean
language plpgsql security definer set search_path='' as $$
declare recent boolean;
begin
 if auth.uid() is null then return false; end if;
 select exists(select 1 from public.social_reports r where r.alerted and r.created_at>now()-interval '10 minutes') into recent;
 update public.social_reports r set alerted=true
  where r.reporter=auth.uid() and not r.alerted and r.created_at>now()-interval '5 minutes';
 return found and not recent;
end $$;
commit;
