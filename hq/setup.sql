-- ============================================================
-- EBG HQ Portal — Supabase SQL Setup
-- Run this entire file in your Supabase SQL Editor
-- Project: krchnbfpqcibmcggjvtm.supabase.co
-- ============================================================

-- ─────────────────────────────────────────
-- 1. EXTENSIONS
-- ─────────────────────────────────────────
create extension if not exists "uuid-ossp";

-- ─────────────────────────────────────────
-- 2. ADMIN USERS TABLE
-- ─────────────────────────────────────────
create table if not exists admin_users (
  id        uuid primary key default uuid_generate_v4(),
  user_id   uuid references auth.users(id) on delete cascade unique not null,
  email     text not null
);

alter table admin_users enable row level security;

-- Admins can see the admin table; no one else can
create policy "Admins can read admin_users"
  on admin_users for select
  using (auth.uid() = user_id);

-- ─────────────────────────────────────────
-- 3. is_admin() HELPER FUNCTION
-- ─────────────────────────────────────────
create or replace function is_admin()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from admin_users where user_id = auth.uid()
  );
$$;

-- ─────────────────────────────────────────
-- 4. AUTO-PROMOTE ADMIN ON SIGNUP
--    Automatically adds hello@ebgcreative.ca to admin_users
-- ─────────────────────────────────────────
create or replace function handle_new_user()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.email = 'hello@ebgcreative.ca' then
    insert into admin_users (user_id, email)
    values (new.id, new.email)
    on conflict (user_id) do nothing;
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure handle_new_user();

-- ─────────────────────────────────────────
-- 5. CLIENTS TABLE
-- ─────────────────────────────────────────
create table if not exists clients (
  id                uuid primary key default uuid_generate_v4(),
  user_id           uuid references auth.users(id) on delete set null,
  business_name     text not null,
  contact_name      text,
  email             text,
  phone             text,
  website           text,
  industry          text,
  services          jsonb default '[]',
  project_phase     text default 'Onboarding',
  start_date        date,
  launch_date       date,
  goals             text,
  brand_colours     text,
  brand_fonts       text,
  brand_personality text,
  target_audience   text,
  notes             text,
  is_active         boolean default true,
  created_at        timestamptz default now(),
  updated_at        timestamptz default now()
);

alter table clients enable row level security;

create policy "Admins can do everything with clients"
  on clients for all
  using (is_admin());

create policy "Clients can read their own record"
  on clients for select
  using (user_id = auth.uid());

-- ─────────────────────────────────────────
-- 6. MILESTONES TABLE
-- ─────────────────────────────────────────
create table if not exists milestones (
  id           uuid primary key default uuid_generate_v4(),
  client_id    uuid references clients(id) on delete cascade not null,
  title        text not null,
  description  text,
  due_date     date,
  completed    boolean default false,
  completed_at timestamptz,
  sort_order   int default 0,
  created_at   timestamptz default now()
);

alter table milestones enable row level security;

create policy "Admins can manage milestones"
  on milestones for all
  using (is_admin());

create policy "Clients can read their milestones"
  on milestones for select
  using (
    exists (
      select 1 from clients
      where clients.id = milestones.client_id
        and clients.user_id = auth.uid()
    )
  );

-- ─────────────────────────────────────────
-- 7. BRAND ASSETS TABLE
-- ─────────────────────────────────────────
create table if not exists brand_assets (
  id         uuid primary key default uuid_generate_v4(),
  client_id  uuid references clients(id) on delete cascade not null,
  name       text not null,
  asset_type text not null, -- logo, font, colour, template, document, image, other
  file_url   text,
  file_name  text,
  file_size  bigint,
  colour_hex text,
  notes      text,
  created_at timestamptz default now()
);

alter table brand_assets enable row level security;

create policy "Admins can manage brand assets"
  on brand_assets for all
  using (is_admin());

create policy "Clients can read their brand assets"
  on brand_assets for select
  using (
    exists (
      select 1 from clients
      where clients.id = brand_assets.client_id
        and clients.user_id = auth.uid()
    )
  );

-- ─────────────────────────────────────────
-- 8. APPROVALS TABLE
-- ─────────────────────────────────────────
create table if not exists approvals (
  id             uuid primary key default uuid_generate_v4(),
  client_id      uuid references clients(id) on delete cascade not null,
  title          text not null,
  description    text,
  file_urls      jsonb default '[]',
  status         text default 'pending', -- pending, approved, revision_requested
  revision_notes text,
  created_at     timestamptz default now(),
  updated_at     timestamptz default now()
);

alter table approvals enable row level security;

create policy "Admins can manage approvals"
  on approvals for all
  using (is_admin());

create policy "Clients can read and update their approvals"
  on approvals for select
  using (
    exists (
      select 1 from clients
      where clients.id = approvals.client_id
        and clients.user_id = auth.uid()
    )
  );

create policy "Clients can update approval status"
  on approvals for update
  using (
    exists (
      select 1 from clients
      where clients.id = approvals.client_id
        and clients.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from clients
      where clients.id = approvals.client_id
        and clients.user_id = auth.uid()
    )
  );

-- ─────────────────────────────────────────
-- 9. REQUESTS TABLE
-- ─────────────────────────────────────────
create table if not exists requests (
  id           uuid primary key default uuid_generate_v4(),
  client_id    uuid references clients(id) on delete cascade not null,
  subject      text not null,
  message      text,
  request_type text default 'general', -- general, revision, question, idea
  status       text default 'open',   -- open, in_review, resolved
  created_at   timestamptz default now(),
  updated_at   timestamptz default now()
);

alter table requests enable row level security;

create policy "Admins can manage requests"
  on requests for all
  using (is_admin());

create policy "Clients can manage their own requests"
  on requests for all
  using (
    exists (
      select 1 from clients
      where clients.id = requests.client_id
        and clients.user_id = auth.uid()
    )
  );

-- ─────────────────────────────────────────
-- 10. UPDATES (FEED) TABLE
-- ─────────────────────────────────────────
create table if not exists updates (
  id          uuid primary key default uuid_generate_v4(),
  client_id   uuid references clients(id) on delete cascade not null,
  message     text not null,
  update_type text default 'general', -- general, milestone, approval, file
  created_at  timestamptz default now()
);

alter table updates enable row level security;

create policy "Admins can manage updates"
  on updates for all
  using (is_admin());

create policy "Clients can read their updates"
  on updates for select
  using (
    exists (
      select 1 from clients
      where clients.id = updates.client_id
        and clients.user_id = auth.uid()
    )
  );

-- ─────────────────────────────────────────
-- 11. STORAGE BUCKET FOR BRAND ASSETS
-- ─────────────────────────────────────────
insert into storage.buckets (id, name, public)
values ('brand-assets', 'brand-assets', false)
on conflict (id) do nothing;

-- Admins can upload/download/delete
create policy "Admins manage brand asset files"
  on storage.objects for all
  using (bucket_id = 'brand-assets' and is_admin());

-- Clients can download their own files
-- (relies on folder structure: brand-assets/{client_id}/...)
create policy "Clients can download their files"
  on storage.objects for select
  using (
    bucket_id = 'brand-assets'
    and exists (
      select 1 from clients
      where clients.id::text = split_part(name, '/', 1)
        and clients.user_id = auth.uid()
    )
  );

-- ─────────────────────────────────────────
-- 12. UPDATED_AT TRIGGER HELPER
-- ─────────────────────────────────────────
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger clients_updated_at
  before update on clients
  for each row execute procedure set_updated_at();

create trigger approvals_updated_at
  before update on approvals
  for each row execute procedure set_updated_at();

create trigger requests_updated_at
  before update on requests
  for each row execute procedure set_updated_at();

-- ─────────────────────────────────────────
-- DONE! Next steps:
-- 1. Run this file in Supabase SQL Editor
-- 2. Go to Authentication > Settings > enable Email/Password sign-in
-- 3. Sign up at hq.ebgcreative.ca/hq/ with hello@ebgcreative.ca
--    The trigger will auto-grant you admin access.
-- ─────────────────────────────────────────
