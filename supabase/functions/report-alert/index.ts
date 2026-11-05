// Needs secret REPORT_ALERT_WEBHOOK_URL, a Discord or Slack webhook. See SUPABASE_SETUP.md.
import { reportAlert } from './alert.js';

Deno.serve((request) => reportAlert(request, Deno.env.toObject()));
