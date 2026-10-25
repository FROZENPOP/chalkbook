# Hosting friend invitations

`invite.html` is a static, dependency-free landing page. Host this directory on an HTTPS static host/domain you control. Set `inviteWebBaseURL` in the ignored `ClimbingApp/Social/Supabase.local.json` to that directory's HTTPS URL, then rebuild. Share links will look like `https://YOUR_DOMAIN/invite.html?id=UUID&username=handle`.

The landing page has an explicit Open in Climb Log button and username fallback. It does not claim an App Store release or send friend requests. It opens the registered `climblog://friend/UUID` scheme. The default app/QR link works for installed builds even without web hosting.

Automatic universal-link opening is a separate deployment step: provide the Apple application identifier and domain, serve an `apple-app-site-association` file for `/invite.html`, and add that domain to Associated Domains in Xcode. Until those verified values exist, use the explicit app-opening button; no unverified association or developer-team ID is embedded here.

Do not host this HTML directly on a default Supabase project URL: Supabase restricts HTML rendering on shared project domains. A static web host or a configured custom domain is required. No secrets, cookies, analytics, contact upload, or automatic redirects are used.
