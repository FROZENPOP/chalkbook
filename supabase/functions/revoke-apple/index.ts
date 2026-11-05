// Needs secrets APPLE_PRIVATE_KEY, APPLE_KEY_ID, APPLE_TEAM_ID and APPLE_CLIENT_ID. See SUPABASE_SETUP.md.
import { revokeApple } from './revoke.js';

Deno.serve((request) => revokeApple(request, Deno.env.toObject()));
