-- In-app account deletion (App Store Guideline 5.1.1(v)). Deleting the auth user cascades
-- to the profile, friendships, shared entries, reactions, blocks and reports.
create function social_private.delete_account() returns void
language plpgsql security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 delete from auth.users where id=auth.uid();
end;
$$;

revoke all on function social_private.delete_account() from public,anon;
grant execute on function social_private.delete_account() to authenticated;

create function public.delete_account() returns void
language sql security invoker set search_path='' as $$
 select social_private.delete_account();
$$;

revoke all on function public.delete_account() from public,anon;
grant execute on function public.delete_account() to authenticated;
