// Server-side input checks that hold even when the app is bypassed. Run with Node and @electric-sql/pglite (0.5.11).
import { readFile, readdir } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const db = new PGlite();
await db.exec(`create role anon; create role authenticated;
create schema auth; create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as
$$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
grant usage on schema auth to authenticated,anon;
grant execute on function auth.uid() to authenticated,anon;`);
for (const file of (await readdir(new URL('../migrations/',import.meta.url))).filter(x=>x.endsWith('.sql') && !x.includes('journal_and_places')).sort()) {
 await db.exec(await readFile(new URL('../migrations/'+file,import.meta.url),'utf8'));
}
const a = '00000000-0000-0000-0000-000000000001';
await db.query('insert into auth.users values($1)',[a]);
await db.query("select set_config('request.jwt.claim.sub',$1,false)",[a]); await db.exec('set role authenticated');
const profile = (name, display, avatar = null) => db.query('select public.save_social_profile_v2($1,$2,false,$3,$4)',[name,display,'',avatar]);
const share = day => db.query("select public.save_shared_session($1,'friends','',$2,null,1,null,'Sends only')",[randomUUID(),day]);

// Names: no invisible, spoofing or staff-looking names.
for (const display of ['​', ' ', 'Bob‮evil', 'Line\nbreak', 'Chalkbook Support'])
  await assert.rejects(profile('alice', display), /check constraint/, JSON.stringify(display));
for (const name of ['support', 'admin', 'chalkbook_team'])
  await assert.rejects(profile(name, 'Alice'), /check constraint/, name);
await assert.rejects(profile('alice', 'Alice', Buffer.from('not a jpeg').toString('base64')), /avatar_is_jpeg/);
await profile('alice', 'Alicé 🧗', Buffer.from('ffd8ffe0','hex').toString('base64'));

// Session days must be real dates, not far in the future.
await assert.rejects(share('9999-12-31'), /Invalid session day/);
await assert.rejects(share('2026-99-99'));
await assert.rejects(share('1999-12-31'), /Invalid session day/);
await share(new Date().toISOString().slice(0,10));
const entry = (await db.query('select id from public.shared_sessions limit 1')).rows[0].id;

// Comments must have visible text, and at most 10 a minute.
await assert.rejects(db.query('select public.add_session_comment($1,$2)',[entry,' ​']), /check constraint/);
for (let i = 0; i < 10; i++) await db.query('select public.add_session_comment($1,$2)',[entry,`nice ${i}`]);
await assert.rejects(db.query('select public.add_session_comment($1,$2)',[entry,'one more']), /Too many comments/);
console.log('input limit checks passed');
