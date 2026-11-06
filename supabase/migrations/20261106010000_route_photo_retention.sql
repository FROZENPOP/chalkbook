-- Route photos on posts are temporary copies; the originals stay in the poster's journal on their iPhone.
-- Keep them for 30 days and on each climber's 10 newest photo posts, so one account can't fill the database.
begin;
alter table public.shared_route_photos add column created_at timestamptz not null default now();
create index shared_route_photos_created_at on public.shared_route_photos(created_at);

create or replace function social_private.save_shared_session_with_photos(source_session_id uuid, visibility text, caption text, session_day text,
 attempts integer, sends integer, duration_minutes integer, completeness text, photos jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare entry uuid; photo jsonb; ordinal integer:=0;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if photos is null or jsonb_typeof(photos)<>'array' or jsonb_array_length(photos)>3 then raise exception 'Invalid photo selection'; end if;
 perform social_private.save_shared_session($1,$2,$3,$4,$5,$6,$7,$8);
 select s.id into strict entry from public.shared_sessions s where s.owner_id=auth.uid() and s.source_session_id=$1;
 delete from public.shared_route_photos p where p.entry_id=entry;
 for photo in select value from jsonb_array_elements(photos) loop
  if jsonb_typeof(photo)<>'object' or not(photo ? 'id' and photo ? 'original_base64') or
     exists(select 1 from jsonb_object_keys(photo) k where k not in ('id','original_base64','highlighted_base64')) then raise exception 'Invalid photo fields'; end if;
  insert into public.shared_route_photos(id,entry_id,position,original_base64,highlighted_base64)
   values((photo->>'id')::uuid,entry,ordinal,photo->>'original_base64',photo->>'highlighted_base64');
  ordinal:=ordinal+1;
 end loop;
 update public.shared_sessions s set route_photo_count=ordinal where s.id=entry and s.owner_id=auth.uid();

 -- shortcut: expiry runs whenever anyone saves photos, not on a schedule. Storage only grows here, so this bounds it; move to pg_cron if photos must vanish on the dot.
 with gone as (delete from public.shared_route_photos p where p.created_at < now() - interval '30 days' returning p.entry_id)
 update public.shared_sessions s set route_photo_count=0 where s.id in (select g.entry_id from gone g);

 with extra as (
  select p.entry_id from public.shared_route_photos p join public.shared_sessions s on s.id=p.entry_id
  where s.owner_id=auth.uid() and p.entry_id<>entry group by p.entry_id order by max(p.created_at) desc, p.entry_id offset 9
 ), gone as (delete from public.shared_route_photos p where p.entry_id in (select e.entry_id from extra e) returning p.entry_id)
 update public.shared_sessions s set route_photo_count=0 where s.id in (select g.entry_id from gone g);
end;
$$;
commit;
