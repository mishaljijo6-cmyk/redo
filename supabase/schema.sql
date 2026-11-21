-- redo community marketplace schema for Supabase.
-- Run once in Supabase Dashboard > SQL Editor after creating a project.
-- All user-facing tables use RLS; no service-role key belongs in the browser.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'redo member',
  avatar_url text,
  created_at timestamptz not null default now()
);

create table if not exists public.listings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 3 and 70),
  category text not null,
  price numeric(12,2) not null default 0 check (price >= 0),
  description text not null check (char_length(description) between 5 and 4096),
  area text not null,
  subcategory text,
  state text,
  district text,
  town text,
  condition text,
  specs jsonb not null default '{}'::jsonb,
  photo_urls text[] not null default '{}'::text[],
  seller_name text,
  photo_url text,
  status text not null default 'active' check (status in ('active','sold','removed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Upgrade existing installs for the guided ad-posting flow.
alter table public.listings
  add column if not exists subcategory text,
  add column if not exists state text,
  add column if not exists district text,
  add column if not exists town text,
  add column if not exists condition text,
  add column if not exists specs jsonb not null default '{}'::jsonb,
  add column if not exists photo_urls text[] not null default '{}'::text[],
  add column if not exists seller_name text;
alter table public.listings drop constraint if exists listings_description_check;
alter table public.listings drop constraint if exists listings_description_length_check;
alter table public.listings add constraint listings_description_length_check
  check (char_length(description) between 5 and 4096);

create table if not exists public.favorites (
  user_id uuid not null references auth.users(id) on delete cascade,
  listing_id uuid not null references public.listings(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, listing_id)
);

create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  buyer_id uuid not null references auth.users(id) on delete cascade,
  seller_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  last_message_at timestamptz,
  unique (listing_id, buyer_id, seller_id),
  check (buyer_id <> seller_id)
);

-- Contact numbers are private and are only returned by the deal RPC after both
-- members of a conversation explicitly accept the exchange.
create table if not exists public.private_contact_details (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null check (char_length(full_name) between 2 and 100),
  phone_number text not null check (char_length(phone_number) between 7 and 24),
  updated_at timestamptz not null default now()
);

-- Upgrade older installs too: CREATE TABLE IF NOT EXISTS does not add columns
-- to a table created by an earlier version of the schema.
alter table public.private_contact_details
  add column if not exists user_id uuid references auth.users(id) on delete cascade,
  add column if not exists full_name text,
  add column if not exists phone_number text,
  add column if not exists updated_at timestamptz not null default now();
create unique index if not exists private_contact_details_user_id_uidx
  on public.private_contact_details(user_id);

create table if not exists public.conversation_deal_confirmations (
  conversation_id uuid primary key references public.conversations(id) on delete cascade,
  buyer_confirmed_at timestamptz,
  seller_confirmed_at timestamptz,
  updated_at timestamptz not null default now()
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create table if not exists public.saved_searches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 80),
  query text not null default '',
  category text not null default 'all',
  area text not null default '',
  max_price numeric(12,2),
  created_at timestamptz not null default now()
);

create table if not exists public.listing_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  listing_id uuid not null references public.listings(id) on delete cascade,
  reason text not null check (reason in ('scam','counterfeit','wrong_information','prohibited_item','other')),
  details text not null default '' check (char_length(details) <= 1000),
  created_at timestamptz not null default now()
);

create index if not exists listings_active_newest_idx on public.listings(status, created_at desc);
create index if not exists listings_category_area_idx on public.listings(category, area);
create index if not exists favorites_user_idx on public.favorites(user_id);
create index if not exists conversations_buyer_idx on public.conversations(buyer_id, created_at desc);
create index if not exists conversations_seller_idx on public.conversations(seller_id, created_at desc);
create index if not exists messages_conversation_idx on public.messages(conversation_id, created_at);
create index if not exists saved_searches_owner_idx on public.saved_searches(user_id, created_at desc);
create index if not exists listing_reports_listing_idx on public.listing_reports(listing_id, created_at desc);

alter table public.profiles enable row level security;
alter table public.listings enable row level security;
alter table public.favorites enable row level security;
alter table public.conversations enable row level security;
alter table public.private_contact_details enable row level security;
alter table public.conversation_deal_confirmations enable row level security;
alter table public.messages enable row level security;
alter table public.saved_searches enable row level security;
alter table public.listing_reports enable row level security;

revoke all on public.profiles, public.listings, public.favorites, public.conversations, public.messages, public.saved_searches, public.listing_reports from anon, authenticated;
revoke all on public.private_contact_details, public.conversation_deal_confirmations from anon, authenticated;
grant select on public.profiles to anon, authenticated;
grant insert, update on public.profiles to authenticated;
grant select on public.listings to anon, authenticated;
grant insert, update, delete on public.listings to authenticated;
grant select, insert, delete on public.favorites to authenticated;
grant select, insert on public.conversations to authenticated;
grant update (last_message_at) on public.conversations to authenticated;
grant select, insert, update, delete on public.private_contact_details to authenticated;
grant select on public.conversation_deal_confirmations to authenticated;
grant select, insert on public.messages to authenticated;
grant select, insert, delete on public.saved_searches to authenticated;
grant select, insert on public.listing_reports to authenticated;

-- Profiles expose display names and avatars only. Keep phone numbers in Auth, not here.
drop policy if exists "Public profiles are readable" on public.profiles;
create policy "Public profiles are readable" on public.profiles for select to anon, authenticated using (true);
drop policy if exists "Users create their profile" on public.profiles;
create policy "Users create their profile" on public.profiles for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "Users update their profile" on public.profiles;
create policy "Users update their profile" on public.profiles for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- Public visitors can see active ads. Sellers can also see their own inactive ads.
drop policy if exists "Active listings are public" on public.listings;
create policy "Active listings are public" on public.listings for select to anon, authenticated using (status = 'active' or (select auth.uid()) = user_id);
drop policy if exists "Users create their own listings" on public.listings;
create policy "Users create their own listings" on public.listings for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "Users update their own listings" on public.listings;
create policy "Users update their own listings" on public.listings for update to authenticated using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
drop policy if exists "Users delete their own listings" on public.listings;
create policy "Users delete their own listings" on public.listings for delete to authenticated using ((select auth.uid()) = user_id);

-- A favorite is private to its owner.
drop policy if exists "Users read their own favorites" on public.favorites;
create policy "Users read their own favorites" on public.favorites for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "Users save their own favorites" on public.favorites;
create policy "Users save their own favorites" on public.favorites for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "Users remove their own favorites" on public.favorites;
create policy "Users remove their own favorites" on public.favorites for delete to authenticated using ((select auth.uid()) = user_id);

-- Buyers can start a conversation only for an active listing and its actual seller.
drop policy if exists "Participants read conversations" on public.conversations;
create policy "Participants read conversations" on public.conversations for select to authenticated using ((select auth.uid()) in (buyer_id, seller_id));
drop policy if exists "Buyers start listing conversations" on public.conversations;
create policy "Buyers start listing conversations" on public.conversations for insert to authenticated with check (
  buyer_id = (select auth.uid()) and buyer_id <> seller_id and exists (
    select 1 from public.listings l where l.id = listing_id and l.user_id = seller_id and l.status = 'active'
  )
);
drop policy if exists "Participants update conversation activity" on public.conversations;
create policy "Participants update conversation activity" on public.conversations for update to authenticated using (
  (select auth.uid()) in (buyer_id, seller_id)
) with check ((select auth.uid()) in (buyer_id, seller_id));

-- Messages are readable only by either participant and can only be sent by their author.
drop policy if exists "Participants read messages" on public.messages;
create policy "Participants read messages" on public.messages for select to authenticated using (
  exists (select 1 from public.conversations c where c.id = conversation_id and (select auth.uid()) in (c.buyer_id, c.seller_id))
);

drop policy if exists "Users manage only their private contact" on public.private_contact_details;
create policy "Users manage only their private contact" on public.private_contact_details for all to authenticated
using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

drop policy if exists "Conversation members read deal confirmations" on public.conversation_deal_confirmations;
create policy "Conversation members read deal confirmations" on public.conversation_deal_confirmations for select to authenticated using (
  exists (select 1 from public.conversations c where c.id = conversation_id and (select auth.uid()) in (c.buyer_id,c.seller_id))
);

create or replace function public.get_conversation_deal_state(p_conversation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer uuid;
  v_seller uuid;
  v_buyer_ok boolean := false;
  v_seller_ok boolean := false;
  v_contacts jsonb := null;
begin
  select buyer_id,seller_id into v_buyer,v_seller from public.conversations
  where id = p_conversation_id and auth.uid() in (buyer_id,seller_id);
  if not found then raise exception 'Conversation not found or access denied'; end if;
  select coalesce(d.buyer_confirmed_at is not null,false),coalesce(d.seller_confirmed_at is not null,false)
    into v_buyer_ok,v_seller_ok
    from (select 1) seed left join public.conversation_deal_confirmations d on d.conversation_id=p_conversation_id;
  if v_buyer_ok and v_seller_ok then
    select jsonb_build_object(
      'buyer',jsonb_build_object('full_name',buyer.full_name,'phone_number',buyer.phone_number),
      'seller',jsonb_build_object('full_name',seller.full_name,'phone_number',seller.phone_number)
    ) into v_contacts
    from public.private_contact_details buyer, public.private_contact_details seller
    where buyer.user_id=v_buyer and seller.user_id=v_seller;
  end if;
  return jsonb_build_object('buyer_confirmed',v_buyer_ok,'seller_confirmed',v_seller_ok,'contacts',v_contacts);
end;
$$;

create or replace function public.confirm_conversation_deal(p_conversation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_buyer uuid;
  v_seller uuid;
begin
  select buyer_id,seller_id into v_buyer,v_seller from public.conversations
  where id=p_conversation_id and auth.uid() in (buyer_id,seller_id);
  if not found then raise exception 'Conversation not found or access denied'; end if;
  if not exists(select 1 from public.private_contact_details where user_id=auth.uid() and char_length(trim(full_name))>=2 and char_length(trim(phone_number))>=7) then
    raise exception 'Add your name and phone number in Settings before confirming a deal';
  end if;
  if auth.uid()=v_buyer then
    insert into public.conversation_deal_confirmations(conversation_id,buyer_confirmed_at,updated_at)
      values(p_conversation_id,now(),now())
      on conflict(conversation_id) do update set buyer_confirmed_at=coalesce(public.conversation_deal_confirmations.buyer_confirmed_at,excluded.buyer_confirmed_at),updated_at=now();
  else
    insert into public.conversation_deal_confirmations(conversation_id,seller_confirmed_at,updated_at)
      values(p_conversation_id,now(),now())
      on conflict(conversation_id) do update set seller_confirmed_at=coalesce(public.conversation_deal_confirmations.seller_confirmed_at,excluded.seller_confirmed_at),updated_at=now();
  end if;
  return public.get_conversation_deal_state(p_conversation_id);
end;
$$;

revoke all on function public.get_conversation_deal_state(uuid) from public, anon;
revoke all on function public.confirm_conversation_deal(uuid) from public, anon;
grant execute on function public.get_conversation_deal_state(uuid) to authenticated;
grant execute on function public.confirm_conversation_deal(uuid) to authenticated;
drop policy if exists "Participants send messages as themselves" on public.messages;
create policy "Participants send messages as themselves" on public.messages for insert to authenticated with check (
  sender_id = (select auth.uid()) and exists (
    select 1 from public.conversations c where c.id = conversation_id and (select auth.uid()) in (c.buyer_id, c.seller_id)
  )
);

-- Saved filters belong to their user. Reports are private to their reporter.
drop policy if exists "Users read their saved searches" on public.saved_searches;
create policy "Users read their saved searches" on public.saved_searches for select to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "Users save their own searches" on public.saved_searches;
create policy "Users save their own searches" on public.saved_searches for insert to authenticated with check ((select auth.uid()) = user_id);
drop policy if exists "Users delete their saved searches" on public.saved_searches;
create policy "Users delete their saved searches" on public.saved_searches for delete to authenticated using ((select auth.uid()) = user_id);
drop policy if exists "Users read their own reports" on public.listing_reports;
create policy "Users read their own reports" on public.listing_reports for select to authenticated using ((select auth.uid()) = reporter_id);
drop policy if exists "Users report a listing as themselves" on public.listing_reports;
create policy "Users report a listing as themselves" on public.listing_reports for insert to authenticated with check (
  (select auth.uid()) = reporter_id and exists (select 1 from public.listings l where l.id = listing_id and l.status = 'active')
);

-- Public listing photos; each signed-in user can upload/delete only inside their own folder.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('listing-images', 'listing-images', true, 8388608, array['image/jpeg','image/png','image/webp'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Listing images are publicly readable" on storage.objects;
create policy "Listing images are publicly readable" on storage.objects for select to anon, authenticated using (bucket_id = 'listing-images');
drop policy if exists "Users upload listing images to their folder" on storage.objects;
create policy "Users upload listing images to their folder" on storage.objects for insert to authenticated with check (
  bucket_id = 'listing-images' and (storage.foldername(name))[1] = (select auth.uid())::text
);
drop policy if exists "Users delete their listing images" on storage.objects;
create policy "Users delete their listing images" on storage.objects for delete to authenticated using (
  bucket_id = 'listing-images' and (storage.foldername(name))[1] = (select auth.uid())::text
);

-- Enable live message delivery. Realtime is required for the browser chat subscription.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages') then
      alter publication supabase_realtime add table public.messages;
    end if;
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'conversation_deal_confirmations') then
      alter publication supabase_realtime add table public.conversation_deal_confirmations;
    end if;
  end if;
end $$;
