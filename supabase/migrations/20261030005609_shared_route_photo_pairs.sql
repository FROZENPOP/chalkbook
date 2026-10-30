-- Explicit reviewed photo copies, separate from public recap rows. No originals are auto-uploaded.
begin;
alter table public.shared_sessions add column route_photo_count integer not null default 0 check(route_photo_count between 0 and 3);

create function social_private.valid_route_jpeg(encoded text) returns boolean
language plpgsql immutable strict set search_path='' as $$
declare bytes bytea;
begin
 if length(encoded)>174764 or encoded !~ '^[A-Za-z0-9+/]+={0,2}$' then return false; end if;
 begin bytes:=decode(encoded,'base64'); exception when others then return false; end;
 return octet_length(bytes) between 4 and 131072 and substring(bytes from 1 for 3)=decode('ffd8ff','hex');
end;
$$;
revoke all on function social_private.valid_route_jpeg(text) from public,anon;
grant execute on function social_private.valid_route_jpeg(text) to authenticated;

create table public.shared_route_photos (
 id uuid primary key,
 entry_id uuid not null references public.shared_sessions(id) on delete cascade,
 position integer not null check(position between 0 and 2),
 original_base64 text not null check(social_private.valid_route_jpeg(original_base64)),
 highlighted_base64 text check(highlighted_base64 is null or social_private.valid_route_jpeg(highlighted_base64)),
 unique(entry_id,position)
);
alter table public.shared_route_photos enable row level security;
create policy route_photos_read on public.shared_route_photos for select to authenticated using (
 exists(select 1 from public.shared_sessions s where s.id=entry_id and
 (s.owner_id=(select auth.uid()) or (s.visibility in ('friends','public') and social_private.friends(s.owner_id))))
);
revoke all on public.shared_route_photos from public,anon,authenticated;
grant select on public.shared_route_photos to authenticated;

-- Match the existing identity-checked private mutation/public invoker boundary.
create function social_private.save_shared_session_with_photos(source_session_id uuid, visibility text, caption text, session_day text,
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
end;
$$;
revoke all on function social_private.save_shared_session_with_photos(uuid,text,text,text,integer,integer,integer,text,jsonb) from public,anon;
grant execute on function social_private.save_shared_session_with_photos(uuid,text,text,text,integer,integer,integer,text,jsonb) to authenticated;

create function public.save_shared_session_with_photos(source_session_id uuid, visibility text, caption text, session_day text,
 attempts integer, sends integer, duration_minutes integer, completeness text, photos jsonb) returns void
language sql security invoker set search_path='' as $$
 select social_private.save_shared_session_with_photos($1,$2,$3,$4,$5,$6,$7,$8,$9);
$$;
revoke all on function public.save_shared_session_with_photos(uuid,text,text,text,integer,integer,integer,text,jsonb) from public,anon;
grant execute on function public.save_shared_session_with_photos(uuid,text,text,text,integer,integer,integer,text,jsonb) to authenticated;
commit;
