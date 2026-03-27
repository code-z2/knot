pragma foreign_keys = on;

create table users (
  id text primary key,
  created_at integer not null,
  status text not null check (status in ('active', 'revoked'))
);

create table passkeys (
  credential_id text primary key,
  user_id text not null,
  public_key text not null,
  counter integer not null,
  created_at integer not null,
  foreign key (user_id) references users (id)
);

create index passkeys_user_id_idx on passkeys (user_id);

create table app_attestations (
  key_id text primary key,
  public_key text not null unique,
  sign_count integer not null,
  environment text not null check (environment in ('development', 'production')),
  created_at integer not null,
  updated_at integer not null,
  status text not null check (status in ('active', 'revoked'))
);

create table sessions (
  id text primary key,
  access_token text not null unique,
  refresh_token text not null unique,
  app_attest_key_id text not null,
  user_id text not null,
  issued_at integer not null,
  expires_at integer not null,
  status text not null check (status in ('active', 'expired', 'revoked')),
  foreign key (app_attest_key_id) references app_attestations (key_id),
  foreign key (user_id) references users (id)
);

create index sessions_access_token_idx on sessions (access_token);
create index sessions_user_id_idx on sessions (user_id);
create index sessions_app_attest_key_id_idx on sessions (app_attest_key_id);
