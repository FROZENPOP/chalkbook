-- Allow U+200C and U+200D (zero-width non-joiner and joiner): emoji like 🧗‍♀️ and Persian and Indic text need them.
-- Every other control, zero-width and text-direction character stays rejected.
-- not valid, as before: this only loosens the old rules, so rows that passed them pass these.
-- To revert, re-add the definitions from 20261106034710_input_limits.sql and 20261107092139_plain_text.sql.
alter table public.climber_profiles drop constraint display_name_plain,
 add constraint display_name_plain check (display_name !~ '[[:cntrl:]\u200b\u200e\u200f\u202a-\u202e\u2060\u2066-\u2069\ufeff]') not valid;
alter table public.climber_profile_details drop constraint bio_plain,
 add constraint bio_plain check (bio !~ '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u200b\u200e\u200f\u202a-\u202e\u2060\u2066-\u2069\ufeff]') not valid;
alter table public.shared_sessions drop constraint caption_plain,
 add constraint caption_plain check (caption !~ '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u200b\u200e\u200f\u202a-\u202e\u2060\u2066-\u2069\ufeff]') not valid;
alter table public.session_comments drop constraint body_plain,
 add constraint body_plain check (body !~ '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u200b\u200e\u200f\u202a-\u202e\u2060\u2066-\u2069\ufeff]') not valid;
