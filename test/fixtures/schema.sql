-- A realistic slice of a Postgres schema.
set statement_timeout = 0;
create extension if not exists "pgcrypto";

create table users (
  id uuid primary key default gen_random_uuid(),
  email text not null unique,
  display_name text,
  age int,
  tags text[] not null default '{}',
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

create index users_email_idx on users (email);

create table posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references users (id),
  title text not null,
  body text,
  score numeric(10,2),
  created_at timestamptz not null default now(),
  constraint posts_title_not_empty check (length(title) > 0)
);

comment on table posts is 'blog posts';
