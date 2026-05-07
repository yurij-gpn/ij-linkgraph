-- Initial schema — applied 2026-05-07
-- Run in Supabase SQL Editor

create table clusters (
  id text primary key,
  name text not null,
  stroke text,
  fill text,
  created_at timestamptz default now()
);

create table nodes (
  id text primary key,
  label text not null,
  url text,
  cluster_id text references clusters(id) on delete set null,
  source text default 'manual',
  status text default 'active',
  redirect_to text,
  ur integer default 0,
  bl integer default 0,
  rh integer default 0,
  data_date text,
  x float default 360,
  y float default 400,
  notes text,
  created_at timestamptz default now()
);

create table links (
  id text primary key,
  source_id text not null references nodes(id) on delete cascade,
  target_id text not null references nodes(id) on delete cascade,
  type text not null,
  origin text default 'manual',
  anchors text[] default '{}',
  priority text default 'none',
  status text default 'n/a',
  implemented_date text,
  rationale text,
  implementation_notes text,
  notes text,
  created_at timestamptz default now()
);

create table backlinks (
  id text primary key,
  target_node_id text references nodes(id) on delete set null,
  source_url text not null,
  vendor_url text,
  anchor text,
  do_follow text default 'yes',
  bl_status text default 'actual',
  price float default 0,
  currency text default 'USD',
  acquired_date text,
  live_date text,
  notes text,
  created_at timestamptz default now()
);

create table analytics (
  id bigserial primary key,
  month text not null,
  url text not null,
  node_id text references nodes(id) on delete set null,
  cluster_id text references clusters(id) on delete set null,
  clicks integer default 0,
  impressions integer default 0,
  ctr float default 0,
  position float default 0,
  visitors integer default 0,
  pageviews integer default 0,
  bounce_rate float,
  time_on_page float,
  scroll_depth float,
  imported_at text,
  unique(month, url)
);

alter table clusters  enable row level security;
alter table nodes     enable row level security;
alter table links     enable row level security;
alter table backlinks enable row level security;
alter table analytics enable row level security;

create policy "auth_all" on clusters  for all to authenticated using (true) with check (true);
create policy "auth_all" on nodes     for all to authenticated using (true) with check (true);
create policy "auth_all" on links     for all to authenticated using (true) with check (true);
create policy "auth_all" on backlinks for all to authenticated using (true) with check (true);
create policy "auth_all" on analytics for all to authenticated using (true) with check (true);
