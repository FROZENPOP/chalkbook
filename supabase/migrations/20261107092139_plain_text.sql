-- Bios, captions and comments reject the hidden and text-direction characters display names already reject,
-- so nobody can spoof or hide text other climbers read. Tabs and line breaks stay allowed in longer text.
-- not valid: checks every new write; existing rows were checked clean when this was written.
alter table public.climber_profile_details add constraint bio_plain
 check (bio !~ '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u200b-\u200f\u202a-\u202e\u2060\u2066-\u2069\ufeff]') not valid;
alter table public.shared_sessions add constraint caption_plain
 check (caption !~ '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u200b-\u200f\u202a-\u202e\u2060\u2066-\u2069\ufeff]') not valid;
alter table public.session_comments add constraint body_plain
 check (body !~ '[\x01-\x08\x0b\x0c\x0e-\x1f\x7f-\x9f\u200b-\u200f\u202a-\u202e\u2060\u2066-\u2069\ufeff]') not valid;
