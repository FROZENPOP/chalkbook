-- A block belongs to the account, not the social profile. Keyed to profiles, a blocked
-- climber could delete and recreate their profile to silently erase someone's block.
alter table public.climber_blocks
  drop constraint climber_blocks_owner_id_fkey,
  drop constraint climber_blocks_target_id_fkey,
  add constraint climber_blocks_owner_id_fkey foreign key (owner_id) references auth.users(id) on delete cascade,
  add constraint climber_blocks_target_id_fkey foreign key (target_id) references auth.users(id) on delete cascade;

-- Dismissed suggestions had the same cascade, so they came back the same way.
alter table public.friend_suggestion_dismissals
  drop constraint friend_suggestion_dismissals_owner_id_fkey,
  drop constraint friend_suggestion_dismissals_target_id_fkey,
  add constraint friend_suggestion_dismissals_owner_id_fkey foreign key (owner_id) references auth.users(id) on delete cascade,
  add constraint friend_suggestion_dismissals_target_id_fkey foreign key (target_id) references auth.users(id) on delete cascade;
