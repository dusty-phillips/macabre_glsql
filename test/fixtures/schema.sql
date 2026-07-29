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

-- Shapes that push the generated lines past the width gleam formats at:
-- a name at the Postgres identifier limit, and enough columns that the
-- record and the decoder have to wrap.
create table wide_rows (
  id uuid primary key,
  a_column_name_at_the_postgres_identifier_limit_of_sixty_three_x text,
  another_column_that_is_also_quite_long_but_not_null_here_at_all text not null,
  amount numeric(10,2) not null,
  labels text[] not null,
  maybe_labels text[],
  first_field text not null,
  second_field text not null,
  third_field text not null,
  fourth_field text not null,
  fifth_field text not null,
  sixth_field text not null
);
