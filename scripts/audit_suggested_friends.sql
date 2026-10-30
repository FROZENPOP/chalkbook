-- Run only AFTER applying 20261030061722_suggested_friends, with a privileged SQL connection.
-- Shared by the local PostgreSQL harness and the supervisor's hosted audit. All fixtures roll back.
begin;
create temp table suggestion_audit on commit drop as
select array_agg(gen_random_uuid()) ids from generate_series(1,10);
do $$ begin execute format('grant usage on schema %I to authenticated,anon',(select nspname from pg_namespace where oid=pg_my_temp_schema())); end $$;
grant select on suggestion_audit to authenticated,anon;
create function pg_temp.suggestion_assert(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Suggestion audit failed: %',label; end if; end $$;
grant execute on function pg_temp.suggestion_assert(boolean,text) to authenticated,anon;
insert into auth.users(id) select unnest(ids) from suggestion_audit;
insert into public.climber_profiles(id,username,display_name,is_private)
select id,'sugg_'||left(replace(id::text,'-',''),18),case n when 2 then 'Mutual One' when 3 then 'Mutual Two' else 'Suggestion audit '||n end,n<>5
from suggestion_audit cross join lateral unnest(ids) with ordinality u(id,n);
insert into public.climber_profile_details(id,avatar_base64) select ids[4],'YWJj' from suggestion_audit union all select ids[5],'YWJj' from suggestion_audit;
insert into public.friendships(requester,recipient,status)
select ids[a],ids[b],status from suggestion_audit cross join (values
 (1,2,'accepted'),(3,1,'accepted'),(2,4,'accepted'),(4,3,'accepted'),(2,5,'accepted'),
 (2,6,'accepted'),(2,7,'accepted'),(2,8,'accepted'),(2,9,'accepted'),(8,1,'pending')) pairs(a,b,status);
select set_config('request.jwt.claim.sub',ids[6]::text,true) from suggestion_audit;
set local role authenticated;
select public.set_friend_discovery(false);
reset role;
select set_config('request.jwt.claim.sub',ids[7]::text,true) from suggestion_audit;
set local role authenticated;
select public.block_climber(ids[1]) from suggestion_audit;
reset role;
select set_config('request.jwt.claim.sub',ids[1]::text,true) from suggestion_audit;
set local role authenticated;
select public.dismiss_friend_suggestion(ids[9]) from suggestion_audit;
select public.dismiss_friend_suggestion(ids[9]) from suggestion_audit; -- Idempotent across retries/devices.
select pg_temp.suggestion_assert(not exists(select 1 from public.friendships f where
 f.requester<>(select ids[1] from suggestion_audit) and f.recipient<>(select ids[1] from suggestion_audit)),'cannot read another user friend list');
select pg_temp.suggestion_assert((select count(*)=2 from public.suggested_friends()),'self/friends/pending/opt-out/blocked/dismissed excluded');
select pg_temp.suggestion_assert((select id=(select ids[4] from suggestion_audit) and mutual_count=2 and mutual_names=array['Mutual One','Mutual Two']
 and avatar_base64 is null from public.suggested_friends(1,0)),'rank/count/known mutuals and private avatar');
select pg_temp.suggestion_assert((select id=(select ids[5] from suggestion_audit) and avatar_base64='YWJj' from public.suggested_friends(1,1)),'pagination and public avatar');
select pg_temp.suggestion_assert(not exists(select 1 from public.suggested_friends() s cross join lateral jsonb_object_keys(to_jsonb(s)) k
 where k not in ('id','display_name','avatar_base64','mutual_count','mutual_names')),'RPC fields allowlist');
select pg_temp.suggestion_assert(not exists(select 1 from public.friend_discovery_settings),'cannot read another owner opt-out');
select pg_temp.suggestion_assert((select count(*)=1 from public.friend_suggestion_dismissals),'only own dismissals visible');
do $$ begin
 begin insert into public.friend_discovery_settings values((select ids[6] from suggestion_audit),true); raise exception 'Unexpected write'; exception when insufficient_privilege then null; end;
 begin delete from public.friend_suggestion_dismissals; raise exception 'Unexpected delete'; exception when insufficient_privilege then null; end;
end $$;
select public.friend_action(ids[4],'request') from suggestion_audit;
select pg_temp.suggestion_assert((select status='pending' from public.friendships where recipient=(select ids[4] from suggestion_audit)),'Add only requests; no auto-accept');
select pg_temp.suggestion_assert(not exists(select 1 from public.suggested_friends() where id=(select ids[4] from suggestion_audit)),'outgoing pending excluded');
select public.friend_action(ids[4],'cancel') from suggestion_audit;
select public.block_climber(ids[5]) from suggestion_audit;
select pg_temp.suggestion_assert(not exists(select 1 from public.suggested_friends() where id=(select ids[5] from suggestion_audit)),'forward block excluded');
reset role;
select set_config('request.jwt.claim.sub',ids[10]::text,true) from suggestion_audit;
set local role authenticated;
select pg_temp.suggestion_assert(not exists(select 1 from public.friendships),'stranger cannot read any friend list');
select pg_temp.suggestion_assert(not exists(select 1 from public.friend_suggestion_dismissals),'other owner dismissal hidden');
select pg_temp.suggestion_assert(not exists(select 1 from public.suggested_friends()),'no mutuals means no suggestions');
reset role;
-- Larger isolated graph verifies the hard cap and bounded mutual-name sample.
create temp table suggestion_extra on commit drop as select gen_random_uuid() id from generate_series(1,30);
insert into auth.users(id) select id from suggestion_extra;
insert into public.climber_profiles(id,username,display_name) select id,'sugg_'||left(replace(id::text,'-',''),18),'Extra suggestion' from suggestion_extra;
insert into public.friendships(requester,recipient,status) select ids[2],id,'accepted' from suggestion_audit cross join suggestion_extra;
-- Give the leading candidate five mutuals, so the three-name bound is exercised, not vacuous.
create temp table suggestion_mutuals on commit drop as select gen_random_uuid() id from generate_series(1,3);
insert into auth.users(id) select id from suggestion_mutuals;
insert into public.climber_profiles(id,username,display_name) select id,'sugg_'||left(replace(id::text,'-',''),18),'Extra mutual' from suggestion_mutuals;
insert into public.friendships(requester,recipient,status) select ids[1],id,'accepted' from suggestion_audit cross join suggestion_mutuals
 union all select id,ids[4],'accepted' from suggestion_audit cross join suggestion_mutuals;
select set_config('request.jwt.claim.sub',ids[1]::text,true) from suggestion_audit;
set local role authenticated;
select pg_temp.suggestion_assert((select mutual_count=5 and cardinality(mutual_names)=3 from public.suggested_friends(1,0)),'five mutuals only disclose three names');
select pg_temp.suggestion_assert(not exists(select 1 from public.suggested_friends() s cross join lateral unnest(s.mutual_names) name
 where not exists(select 1 from public.friendships f join public.climber_profiles p on p.id=case when f.requester=(select ids[1] from suggestion_audit) then f.recipient else f.requester end
 where f.status='accepted' and p.display_name=name)),'every disclosed name belongs to caller accepted friends');
select pg_temp.suggestion_assert((select count(*)=20 from public.suggested_friends(999,0)),'hard maximum 20');
select pg_temp.suggestion_assert((select count(*)=1 from public.suggested_friends(-1,-1)),'negative bounds clamped');
select pg_temp.suggestion_assert((select count(*)=10 from public.suggested_friends(null,null)),'null bounds use defaults');
select pg_temp.suggestion_assert(not exists(select 1 from public.suggested_friends(20,10) where cardinality(mutual_names)>3),'mutual names bounded');
select public.set_friend_discovery(false);
select pg_temp.suggestion_assert((select enabled=false from public.friend_discovery_settings),'own opt-out saved');
reset role;
select pg_temp.suggestion_assert(not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='social_private' and p.proname in ('suggested_friends','set_friend_discovery','dismiss_friend_suggestion') and (not p.prosecdef or not coalesce('search_path=""'=any(p.proconfig),false))),'definer search paths');
select pg_temp.suggestion_assert((select bool_and(relrowsecurity) from pg_class where oid in ('public.friend_discovery_settings'::regclass,'public.friend_suggestion_dismissals'::regclass)),'new tables RLS enabled');
select set_config('request.jwt.claim.sub','',true);
set local role authenticated;
do $$ begin
 begin perform public.suggested_friends(); raise exception 'Unexpected null identity'; exception when raise_exception then if sqlerrm<>'Sign in required' then raise; end if; end;
 begin perform social_private.set_friend_discovery(false); raise exception 'Unexpected null identity'; exception when raise_exception then if sqlerrm<>'Sign in required' then raise; end if; end;
end $$;
reset role;
set local role anon;
do $$ begin
 begin perform public.suggested_friends(); raise exception 'Unexpected anonymous RPC'; exception when insufficient_privilege then null; end;
 begin perform public.dismiss_friend_suggestion(gen_random_uuid()); raise exception 'Unexpected anonymous dismissal'; exception when insufficient_privilege then null; end;
 begin perform public.set_friend_discovery(false); raise exception 'Unexpected anonymous setting'; exception when insufficient_privilege then null; end;
 begin perform * from public.friend_discovery_settings; raise exception 'Unexpected anonymous table read'; exception when insufficient_privilege then null; end;
 begin perform * from public.friend_suggestion_dismissals; raise exception 'Unexpected anonymous table read'; exception when insufficient_privilege then null; end;
end $$;
reset role;
rollback;
select 'passed' as suggested_friends_audit,'all synthetic identities and content rolled back' as fixture_status;
