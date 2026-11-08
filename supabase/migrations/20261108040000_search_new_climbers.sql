-- Search stopped finding new climbers after 20261106034711_profile_reads.sql: it ran as the caller, and the
-- table now hides anyone you aren't connected to. It runs as the owner again, still one bounded query at a time
-- (2-60 characters, 30 results), never returns the caller, and skips climbers either side has blocked.
create or replace function public.search_climbers(search_text text) returns setof public.climber_profiles
language sql stable security definer set search_path='' as $$
 with term as (select lower(trim(search_text)) as q),
 pattern as (select q,replace(replace(replace(q,'\','\\'),'%','\%'),'_','\_') as literal from term)
 select p.* from public.climber_profiles p cross join pattern t
 where auth.uid() is not null and length(t.q) between 2 and 60 and p.id<>auth.uid() and not social_private.blocked(p.id) and
  (p.username ilike t.literal||'%' or p.display_name ilike '%'||t.literal||'%')
 order by case when p.username=t.q then 0 when lower(p.display_name)=t.q then 1
  when p.username ilike t.literal||'%' then 2 else 3 end,p.username limit 30
$$;
revoke all on function public.search_climbers(text) from public,anon;
grant execute on function public.search_climbers(text) to authenticated;
