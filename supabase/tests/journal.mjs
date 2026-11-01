// Policy test for the Phase 0 journal, places and follows migration. Run with Node and @electric-sql/pglite (0.5.11).
import { readFile, readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
await db.exec(`create role anon; create role authenticated;
create schema auth; create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated,anon;
grant execute on function auth.uid() to authenticated,anon;`);
const target = '20261031120000_journal_and_places.sql';
const files = (await readdir(new URL('../migrations/', import.meta.url))).filter(x => x.endsWith('.sql')).sort();
const run = async file => db.exec(await readFile(new URL('../migrations/' + file, import.meta.url), 'utf8'));
for (const file of files.filter(x => x < target)) await run(file);

const [a,b,c,d] = [1,2,3,4].map(i => `00000000-0000-0000-0000-00000000000${i}`);
const [s1,a1,a2,p1] = [1,2,3,4].map(i => `20000000-0000-0000-0000-00000000000${i}`);
for (const id of [a,b,c,d]) await db.query('insert into auth.users values($1)',[id]);
async function as(id) { await db.exec('reset role'); await db.query("select set_config('request.jwt.claim.sub',$1,false)",[id]); await db.exec('set role authenticated'); }
async function count(sql) { return (await db.query(sql)).rows.length; }
let checks = 0;
function equal(actual, expected, message) { assert.equal(actual, expected, message); checks++; }
async function denied(sql, message) { await assert.rejects(db.exec(sql), undefined, message); checks++; }
for (const [id,name] of [[a,'alice'],[b,'bob'],[c,'carol'],[d,'dana']]) { await as(id); await db.query('select public.save_social_profile($1,$1,true)',[name]); }
await as(a); await db.query("select public.friend_action($1,'request')",[d]);
await as(d); await db.query("select public.friend_action($1,'accept')",[a]);

await db.exec('reset role'); await run(target);
await as(a); equal(await count('select * from public.follows'), 0, 'friendships are not copied into follows before the cutover');
await db.query("select public.follow_action($1,'follow')",[d]);
await as(d); await db.query("select public.follow_action($1,'approve')",[a]); await db.query("select public.follow_action($1,'follow')",[a]);
await as(a); await db.query("select public.follow_action($1,'approve')",[d]);

// Follows: private profiles approve requests; the requester cannot approve their own.
await as(b); await db.query("select public.follow_action($1,'follow')",[a]);
await db.query("select public.follow_action($1,'approve')",[a]);
equal((await db.query('select status from public.follows')).rows[0].status, 'pending', 'requester cannot approve');
await denied(`insert into public.follows values('${b}','${c}','accepted',now())`, 'follows only change through the RPC');
await as(a); await db.query("select public.follow_action($1,'approve')",[b]);
equal((await db.query(`select status from public.follows where follower_id='${b}'`)).rows[0].status, 'accepted', 'followee approves');
await as(c); await db.exec("select public.save_social_profile('carol','carol',false)");
await as(d); await db.query("select public.follow_action($1,'follow')",[c]);
equal((await db.query(`select status from public.follows where followee_id='${c}'`)).rows[0].status, 'accepted', 'public profile follows auto-accept');

// Shared places: anyone adds, only the creator edits, walls stay within their gym.
await as(a);
const gym = (await db.query("insert into public.gyms(name,apple_place_id,created_by) values('Boulder Barn','place-1',$1) returning id",[a])).rows[0].id;
const otherGym = (await db.query("insert into public.gyms(name,created_by) values('Other Gym',$1) returning id",[a])).rows[0].id;
const wall = (await db.query("insert into public.walls(gym_id,name,created_by) values($1,'Cave',$2) returning id",[otherGym,a])).rows[0].id;
await denied(`insert into public.routes(gym_id,wall_id,created_by) values('${gym}','${wall}','${a}')`, 'a wall from another gym is rejected');
const route = (await db.query("insert into public.routes(gym_id,colour,grade,created_by) values($1,'Blue','V4',$2) returning id",[gym,a])).rows[0].id;
await denied(`insert into public.gyms(name,apple_place_id,created_by) values('Copy','place-1','${a}')`, 'gyms deduplicate on Apple place ID');
await as(c);
await denied(`insert into public.gyms(name,created_by) values('Forged','${a}')`, 'cannot add a gym as someone else');
await db.exec(`update public.routes set grade='V9' where id='${route}'`);
equal((await db.query('select grade from public.routes')).rows[0].grade, 'V4', 'only the creator edits a route');

// Journal: owner writes; the server owns updated_at.
await as(a);
await db.query(`insert into public.sessions(id,owner_id,gym_id,started_at,tz,updated_at) values($1,$2,$3,now(),'Europe/London','2000-01-01')`,[s1,a,gym]);
equal((await db.query('select visibility, updated_at > now() - interval \'1 minute\' as fresh from public.sessions')).rows[0].visibility, 'followers', 'posts default to followers');
equal((await db.query('select updated_at > now() - interval \'1 minute\' as fresh from public.sessions')).rows[0].fresh, true, 'server sets updated_at');
await db.query(`insert into public.attempts(id,session_id,owner_id,route_id,seq,sent,at) values($1,$2,$3,$4,1,true,now())`,[a1,s1,a,route]);
await db.query(`insert into public.personal_routes(id,owner_id,grade) values($1,$2,'6a')`,[p1,a]);
await db.query(`insert into public.attempts(id,session_id,owner_id,personal_route_id,seq,sent,at) values($1,$2,$3,$4,2,false,now())`,[a2,s1,a,p1]);
await db.query(`insert into public.sessions(id,owner_id,started_at,tz) values($1,$2,now(),'UTC') on conflict(id) do update set caption='Upserted'`,[s1,a]);
equal((await db.query('select caption from public.sessions')).rows[0].caption, 'Upserted', 'outbox upserts are idempotent');
await as(c);
await denied(`insert into public.sessions(id,owner_id,started_at,tz) values(gen_random_uuid(),'${a}',now(),'UTC')`, 'cannot create a session for someone else');
await denied(`insert into public.sessions(id,owner_id,started_at,tz) values('${s1}','${c}',now(),'UTC') on conflict(id) do update set caption='Hijack'`, 'upsert cannot take over another owner\'s id');
await db.query(`insert into public.sessions(id,owner_id,started_at,tz) values('30000000-0000-0000-0000-000000000001',$1,now(),'UTC')`,[c]);
await denied(`insert into public.attempts(id,session_id,owner_id,seq,sent,at) values(gen_random_uuid(),'${s1}','${c}',3,true,now())`, 'cannot log into another climber\'s session');
await denied(`insert into public.attempts(id,session_id,owner_id,personal_route_id,seq,sent,at) values(gen_random_uuid(),'30000000-0000-0000-0000-000000000001','${c}','${p1}',1,true,now())`, 'cannot use another climber\'s personal route');
await db.exec(`update public.sessions set caption='Forged' where id='${s1}'`);
await denied(`delete from public.sessions where id='${s1}'`, 'deletes are tombstones, never hard deletes');
await as(a); equal((await db.query(`select caption from public.sessions where id='${s1}'`)).rows[0].caption, 'Upserted', 'others cannot edit a session');

// Visibility: followers see followers posts; private hides everything; public needs a public profile.
const sees = async (id, n, message) => { await as(id); equal(await count(`select * from public.sessions where id='${s1}'`) + await count(`select * from public.attempts where session_id='${s1}'`), n, message); };
await sees(b, 3, 'follower sees the session and both attempts');
await sees(c, 0, 'non-follower cannot see a followers post');
await sees(d, 3, 'mutual follower sees the session');
await as(a); await db.exec(`update public.sessions set visibility='private' where id='${s1}'`);
await sees(b, 0, 'a private session is invisible to a follower');
await as(a); await db.exec(`update public.sessions set visibility='public' where id='${s1}'`);
await sees(c, 0, 'public posts stay hidden while the profile is private');
await as(a); await db.exec("select public.save_social_profile('alice','alice',false)");
await sees(c, 3, 'public post on a public profile is visible to anyone signed in');
await as(a); await db.exec(`update public.sessions set hide_gym=true where id='${s1}'`);
await sees(c, 0, 'hidden-gym sessions are not exposed to others yet');
await as(a); await db.exec(`update public.sessions set hide_gym=false, visibility='followers' where id='${s1}'`);
await as(a); await db.exec(`update public.attempts set deleted_at=now() where id='${a2}'`);
await sees(b, 2, 'tombstoned attempts disappear for others');
await sees(a, 3, 'owners still sync their tombstones');
await as(a); await db.exec(`insert into public.media(id,owner_id,session_id,kind,storage_path,visibility) values(gen_random_uuid(),'${a}','${s1}','photo','${a}/1.jpg','private')`);
await denied(`insert into public.media(id,owner_id,session_id,kind,storage_path) values(gen_random_uuid(),'${a}','${s1}','photo','${b}/private.jpg')`, 'media rows cannot point at another climber\'s files');
await db.exec(`insert into public.media(id,owner_id,session_id,kind,storage_path) values(gen_random_uuid(),'${a}','${s1}','photo','${a}/2.jpg')`);
await as(b); equal(await count('select * from public.media'), 1, 'private media stays with the owner');
await as(a); await db.exec(`insert into public.route_notes(id,owner_id,route_id,body) values(gen_random_uuid(),'${a}','${route}','Heel hook left')`);
await as(b); equal(await count('select * from public.route_notes') + await count('select * from public.personal_routes'), 0, 'notes and personal routes are private');

// Kudos and comments follow session visibility; owners moderate; blocks cut everything.
await as(b); await db.query('insert into public.kudos(session_id,user_id) values($1,$2)',[s1,b]);
await db.query("insert into public.comments(session_id,user_id,body) values($1,$2,'Strong!')",[s1,b]);
await as(c);
await denied(`insert into public.kudos(session_id,user_id) values('${s1}','${c}')`, 'cannot give kudos to an invisible session');
await denied(`insert into public.kudos(session_id,user_id) values('${s1}','${b}')`, 'cannot give kudos as someone else');
await as(a); equal(await count('select * from public.kudos') + await count('select * from public.comments'), 2, 'owner sees kudos and comments');
await db.exec(`delete from public.comments where session_id='${s1}'`);
equal(await count('select * from public.comments'), 0, 'owner removes comments on their post');
await db.query('select public.block_climber($1)',[b]);
await as(b); equal(await count('select * from public.sessions') + await count('select * from public.follows'), 0, 'blocking hides sessions and removes follows');
await as(a); equal(await count('select * from public.kudos'), 0, 'blocked climbers\' kudos are hidden');

await db.exec('reset role; set role anon');
await denied('select * from public.sessions', 'signed-out clients read nothing');
await db.close();
console.log(`Journal, places and follows policy test passed (${checks} checks).`);
