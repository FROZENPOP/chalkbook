-- Synthetic users and byte markers exercise authorization, not JPEG decoding. Everything rolls back.
begin;
create temp table photo_audit on commit drop as select gen_random_uuid() a,gen_random_uuid() b,gen_random_uuid() c,gen_random_uuid() source,gen_random_uuid() photo;
do $$ begin execute format('grant usage on schema %I to authenticated,anon',(select nspname from pg_namespace where oid=pg_my_temp_schema())); end $$;
grant select on photo_audit to authenticated,anon;
create function pg_temp.check_photo(ok boolean,label text) returns void language plpgsql as $$
begin if ok is distinct from true then raise exception 'Photo audit failed: %',label; end if; end $$;
grant execute on function pg_temp.check_photo(boolean,text) to authenticated,anon;
insert into auth.users(id) select a from photo_audit union all select b from photo_audit union all select c from photo_audit;
select set_config('request.jwt.claim.sub',a::text,true) from photo_audit;
set local role authenticated;
select public.save_social_profile('pa_'||left(replace(a::text,'-',''),12),'Photo audit A',false) from photo_audit;
select public.save_shared_session_with_photos(source,'public','Reviewed photo','2026-10-29',null,null,null,'Unknown',
 jsonb_build_array(jsonb_build_object('id',photo,'original_base64','/9j/2Q==','highlighted_base64','/9j/2Q=='))) from photo_audit;
select pg_temp.check_photo((select count(*)=1 from public.shared_route_photos),'owner sees both versions');
select pg_temp.check_photo((select original_base64 is not null and highlighted_base64 is not null from public.shared_route_photos),'pair retained');
reset role;
select set_config('request.jwt.claim.sub',b::text,true) from photo_audit;
set local role authenticated;
select public.save_social_profile('pb_'||left(replace(b::text,'-',''),12),'Photo audit B',false) from photo_audit;
select pg_temp.check_photo(exists(select 1 from public.shared_sessions where owner_id=(select a from photo_audit)),'public summary readable');
select pg_temp.check_photo(not exists(select 1 from public.shared_route_photos),'public entry does not expose photos to strangers');
select public.friend_action(a,'request') from photo_audit;
reset role;
select set_config('request.jwt.claim.sub',a::text,true) from photo_audit;
set local role authenticated;
select public.friend_action(b,'accept') from photo_audit;
reset role;
select set_config('request.jwt.claim.sub',b::text,true) from photo_audit;
set local role authenticated;
select pg_temp.check_photo((select count(*)=1 from public.shared_route_photos),'accepted friend sees pair');
do $$ begin
 begin insert into public.shared_route_photos(id,entry_id,position,original_base64) select gen_random_uuid(),id,1,'/9j/2Q==' from public.shared_sessions; raise exception 'Unexpected write'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select set_config('request.jwt.claim.sub',a::text,true) from photo_audit;
set local role authenticated;
select public.save_shared_session(source,'private','','2026-10-29',null,null,null,'Unknown') from photo_audit;
reset role;
select set_config('request.jwt.claim.sub',b::text,true) from photo_audit;
set local role authenticated;
select pg_temp.check_photo(not exists(select 1 from public.shared_route_photos),'private entry revokes photos from friends');
reset role;
select set_config('request.jwt.claim.sub',a::text,true) from photo_audit;
set local role authenticated;
select public.save_shared_session(source,'friends','','2026-10-29',null,null,null,'Unknown') from photo_audit;
-- Invalid replacement must roll back the whole RPC, preserving the prior summary and photos.
do $$ begin
 begin
  perform public.save_shared_session_with_photos((select source from photo_audit),'friends','SHOULD ROLL BACK','2026-10-29',null,null,null,'Unknown',
   jsonb_build_array(jsonb_build_object('id',gen_random_uuid(),'original_base64','invalid')));
  raise exception 'Unexpected invalid image';
 exception when check_violation then null; end;
end $$;
select pg_temp.check_photo((select count(*)=1 from public.shared_route_photos),'failed replacement preserves pair');
select pg_temp.check_photo(not exists(select 1 from public.shared_sessions where caption='SHOULD ROLL BACK'),'failed replacement is atomic');
select public.block_climber(b) from photo_audit;
reset role;
select set_config('request.jwt.claim.sub',b::text,true) from photo_audit;
set local role authenticated;
select pg_temp.check_photo(not exists(select 1 from public.shared_route_photos),'block revokes photo access');
reset role;
select set_config('request.jwt.claim.sub',a::text,true) from photo_audit;
set local role authenticated;
select public.save_shared_session_with_photos(source,'friends','','2026-10-29',null,null,null,'Unknown','[]'::jsonb) from photo_audit;
select pg_temp.check_photo(not exists(select 1 from public.shared_route_photos),'explicit removal deletes shared pair');
select public.save_shared_session_with_photos(source,'friends','','2026-10-29',null,null,null,'Unknown',
 jsonb_build_array(jsonb_build_object('id',photo,'original_base64','/9j/2Q=='))) from photo_audit;
select public.remove_shared_session(source) from photo_audit;
select pg_temp.check_photo(not exists(select 1 from public.shared_route_photos),'deleting recap cascades to photos');
reset role;
select set_config('request.jwt.claim.sub','',true);
set local role anon;
do $$ begin
 begin perform * from public.shared_route_photos;raise exception 'Unexpected anonymous read';exception when insufficient_privilege then null;end;
 begin perform public.save_shared_session_with_photos(gen_random_uuid(),'public','','2026-10-29',null,null,null,'Unknown','[]');raise exception 'Unexpected anonymous write';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
select 'passed' as route_photo_permission_audit, 'all synthetic users and content rolled back' as fixture_status;
