-- ResearchOS Supabase Schema Setup
-- Run this SQL in your Supabase SQL Editor to initialize the database tables and Row Level Security policies.

-- 1. Create Tables

-- Public Users table (mirrors auth.users)
create table public.users (
  id uuid references auth.users on delete cascade primary key,
  email text,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Research Projects Table (collections of queries/reports)
create table public.research_projects (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references public.users(id) on delete cascade not null,
  title text not null,
  created_at timestamp with time zone default timezone('utc'::text, now()) not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Research Queries Table
create table public.research_queries (
  id uuid default gen_random_uuid() primary key,
  project_id uuid references public.research_projects(id) on delete cascade not null,
  query text not null,
  status text not null check (status in ('pending', 'searching', 'scraping', 'extracting', 'verifying', 'completed', 'failed')),
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Research Results Table (1-to-1 with queries)
create table public.research_results (
  id uuid default gen_random_uuid() primary key,
  query_id uuid references public.research_queries(id) on delete cascade unique not null,
  primary_answer text not null,
  confidence_score float not null, -- e.g. 0.92 (92%)
  confidence_level text not null check (confidence_level in ('High', 'Medium', 'Low')),
  summary text,
  insights jsonb default '[]'::jsonb, -- array of text
  contradictions jsonb default '[]'::jsonb, -- array of text
  predictions jsonb default '[]'::jsonb, -- array of text
  key_statistics jsonb default '{}'::jsonb, -- key-value pairs
  timeline jsonb default '[]'::jsonb, -- array of events
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Citations Table (referenced by results)
create table public.citations (
  id uuid default gen_random_uuid() primary key,
  result_id uuid references public.research_results(id) on delete cascade not null,
  url text not null,
  title text not null,
  snippet text,
  extracted_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Images Table (scraped / chart assets for results)
create table public.images (
  id uuid default gen_random_uuid() primary key,
  result_id uuid references public.research_results(id) on delete cascade not null,
  url text not null,
  alt_text text,
  image_type text check (image_type in ('product', 'chart', 'logo', 'infographic', 'other')),
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- Reports Table
create table public.reports (
  id uuid default gen_random_uuid() primary key,
  project_id uuid references public.research_projects(id) on delete cascade not null,
  content text not null, -- markdown report body
  format text not null check (format in ('pdf', 'markdown', 'json', 'csv')),
  created_at timestamp with time zone default timezone('utc'::text, now()) not null
);

-- 2. Indexes for Performance

create index idx_projects_user_id on public.research_projects(user_id);
create index idx_queries_project_id on public.research_queries(project_id);
create index idx_results_query_id on public.research_results(query_id);
create index idx_citations_result_id on public.citations(result_id);
create index idx_images_result_id on public.images(result_id);
create index idx_reports_project_id on public.reports(project_id);

-- 3. Row Level Security Policies (RLS)

alter table public.users enable row level security;
alter table public.research_projects enable row level security;
alter table public.research_queries enable row level security;
alter table public.research_results enable row level security;
alter table public.citations enable row level security;
alter table public.images enable row level security;
alter table public.reports enable row level security;

-- Users Policies
create policy "Allow users to view their own profile" on public.users
  for select using (auth.uid() = id);

create policy "Allow users to update their own profile" on public.users
  for update using (auth.uid() = id);

-- Projects Policies (bound to user_id)
create policy "Allow users to view their own projects" on public.research_projects
  for select using (auth.uid() = user_id);

create policy "Allow users to create projects" on public.research_projects
  for insert with check (auth.uid() = user_id);

create policy "Allow users to update their own projects" on public.research_projects
  for update using (auth.uid() = user_id);

create policy "Allow users to delete their own projects" on public.research_projects
  for delete using (auth.uid() = user_id);

-- Queries Policies (bound via projects)
create policy "Allow users to view queries in their projects" on public.research_queries
  for select using (
    exists (
      select 1 from public.research_projects
      where research_projects.id = research_queries.project_id
      and research_projects.user_id = auth.uid()
    )
  );

create policy "Allow users to create queries in their projects" on public.research_queries
  for insert with check (
    exists (
      select 1 from public.research_projects
      where research_projects.id = research_queries.project_id
      and research_projects.user_id = auth.uid()
    )
  );

create policy "Allow users to delete queries in their projects" on public.research_queries
  for delete using (
    exists (
      select 1 from public.research_projects
      where research_projects.id = research_queries.project_id
      and research_projects.user_id = auth.uid()
    )
  );

-- Results Policies (bound via queries)
create policy "Allow users to view results of their queries" on public.research_results
  for select using (
    exists (
      select 1 from public.research_queries
      join public.research_projects on research_projects.id = research_queries.project_id
      where research_queries.id = research_results.query_id
      and research_projects.user_id = auth.uid()
    )
  );

create policy "Allow users to create results of their queries" on public.research_results
  for insert with check (
    exists (
      select 1 from public.research_queries
      join public.research_projects on research_projects.id = research_queries.project_id
      where research_queries.id = research_results.query_id
      and research_projects.user_id = auth.uid()
    )
  );

-- Citations Policies (bound via results)
create policy "Allow users to view citations of their results" on public.citations
  for select using (
    exists (
      select 1 from public.research_results
      join public.research_queries on research_queries.id = research_results.query_id
      join public.research_projects on research_projects.id = research_queries.project_id
      where research_results.id = citations.result_id
      and research_projects.user_id = auth.uid()
    )
  );

create policy "Allow users to insert citations" on public.citations
  for insert with check (
    exists (
      select 1 from public.research_results
      join public.research_queries on research_queries.id = research_results.query_id
      join public.research_projects on research_projects.id = research_queries.project_id
      where research_results.id = citations.result_id
      and research_projects.user_id = auth.uid()
    )
  );

-- Images Policies (bound via results)
create policy "Allow users to view images of their results" on public.images
  for select using (
    exists (
      select 1 from public.research_results
      join public.research_queries on research_queries.id = research_results.query_id
      join public.research_projects on research_projects.id = research_queries.project_id
      where research_results.id = images.result_id
      and research_projects.user_id = auth.uid()
    )
  );

create policy "Allow users to insert images" on public.images
  for insert with check (
    exists (
      select 1 from public.research_results
      join public.research_queries on research_queries.id = research_results.query_id
      join public.research_projects on research_projects.id = research_queries.project_id
      where research_results.id = images.result_id
      and research_projects.user_id = auth.uid()
    )
  );

-- Reports Policies (bound via projects)
create policy "Allow users to view reports of their projects" on public.reports
  for select using (
    exists (
      select 1 from public.research_projects
      where research_projects.id = reports.project_id
      and research_projects.user_id = auth.uid()
    )
  );

create policy "Allow users to create reports of their projects" on public.reports
  for insert with check (
    exists (
      select 1 from public.research_projects
      where research_projects.id = reports.project_id
      and research_projects.user_id = auth.uid()
    )
  );

create policy "Allow users to delete reports" on public.reports
  for delete using (
    exists (
      select 1 from public.research_projects
      where research_projects.id = reports.project_id
      and research_projects.user_id = auth.uid()
    )
  );

-- 4. Automatic User Profile Sync Trigger (Auth -> Public)

create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, email)
  values (new.id, new.email);
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
