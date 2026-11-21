# redo — Good things, found again

This is a responsive static website. Open `index.html` to preview it or deploy the `outputs` folder to Vercel. No build command is needed. For data shared across visitors, connect Supabase as described below.

## Included marketplace flows

- Search, category and location filters, max-price filters, sorting, grid/list views, and listing details.
- Favorites, saved searches, listing share/report actions, editable profile/settings, create/edit/mark-sold/delete listings, image upload, separate buyer and seller inboxes, real-time chat, and mutual Deal OK contact exchange.
- Google OAuth through Supabase Auth; guest browsing keeps favorites on the visitor’s device and requires sign-in before posting or messaging.
- Kerala-first location filtering: all 14 districts with popular towns, plus manual area entry. Location is chosen manually; the site does not request device location permission.
- English / Malayalam interface toggle, persistent light / dark appearance, responsive phone/tablet/desktop layouts, and meaningful category/marketplace photography.

## Connect the Supabase backend

1. Create a Supabase project.
2. In **SQL Editor**, run [`supabase/schema.sql`](supabase/schema.sql). It creates the marketplace tables (including saved searches and reports), storage bucket, indexes, realtime publication membership, and row-level security policies. If you already ran an earlier version, run this updated file again; its table/policy setup is repeatable.
3. Copy `config.example.js` to `config.js`, then add the project URL and **publishable** key. `config.js` is ignored by Git so your local keys are not uploaded. Do not use a secret or service-role key in the browser. Location uses manually selected districts and towns; no Maps key or location permission is needed.
4. Enable Google under **Authentication → Providers → Google**. Configure the OAuth client in the provider dashboard, using the callback URL shown in Supabase.
5. In Supabase **Authentication → URL Configuration**, set **Site URL** to `https://redo-orcin.vercel.app` and add `https://redo-orcin.vercel.app/**` to the allowed redirect URLs. Keep `http://localhost:3000/**` only if you still develop locally. The Google provider’s authorized redirect URI remains the Supabase callback URL shown in Supabase; it is not the Vercel URL.
6. Deploy to Vercel with `outputs` as the project root. Redeploy after editing `config.js`.

Google client secrets should be entered directly in Supabase provider settings, not in `config.js` or the website source. Phone sign-in is not offered in this version. Location is selected manually. Area matching handles common Kattappana/Kattapana spelling differences. For mutual Deal OK contact exchange, make sure you have run the current `supabase/schema.sql` in Supabase SQL Editor, then add your display name and phone under My account → Settings → Profile. Each chat participant must press Deal OK; contact details are revealed only after both sides agree. The phone number is stored in a private table and is not exposed through the public profile. Popular towns are provided for Alappuzha, Ernakulam, Idukki, Kannur, Kasaragod, Kollam, Kottayam, Kozhikode, Malappuram, Palakkad, Pathanamthitta, Thiruvananthapuram, Thrissur and Wayanad.

## Deal OK contact exchange

1. Run the latest `supabase/schema.sql` in Supabase **SQL Editor** (including for an existing project). It adds private contact storage and consent RPCs.
2. Each participant signs in, opens **My account → Settings → Profile**, and saves a display name and phone number with country code.
3. In the conversation, each side presses **Deal OK**. The app reveals both names and phone numbers only after both confirmations. The contact table has row-level security; a user can read or edit only their own contact record.

## Vercel

The linked Vercel project is named **redo** and its production URL is [https://redo-orcin.vercel.app](https://redo-orcin.vercel.app). Deploy directly from a terminal with:

```sh
cd "/home/mishal/Documents/Codex/2026-11-21/create-a-website-like-olx-with/outputs"
npx vercel whoami
npx vercel --prod
```

If `npx vercel whoami` says you are not logged in, run `npx vercel login` once, then run `npx vercel --prod`. The project is already linked, so do not remove `outputs/.vercel`. If Vercel asks for a root directory, use the `outputs` folder. There is no build command.

Guests can browse without signing in; posting, messaging sellers and syncing saved searches require Google sign-in. Favorites stay on the guest’s device until they sign in. Production listings, authentication, image storage and shared conversations require the Supabase setup above.
