create extension if not exists pgcrypto with schema extensions;

create table public.site_state (id int primary key default 1 check (id = 1), data jsonb not null, updated_at timestamptz not null default now());
grant all on public.site_state to service_role;
alter table public.site_state enable row level security;

create table public.panel_accounts (role text primary key check (role in ('admin','tattoo')), username text not null, password_hash text not null);
grant all on public.panel_accounts to service_role;
alter table public.panel_accounts enable row level security;

create table public.panel_sessions (token text primary key, role text not null, expires_at timestamptz not null);
grant all on public.panel_sessions to service_role;
alter table public.panel_sessions enable row level security;

insert into public.panel_accounts values
 ('admin','Arthur Lima', extensions.crypt('1389', extensions.gen_salt('bf'))),
 ('tattoo','Cenin', extensions.crypt('1010', extensions.gen_salt('bf')));

create or replace function public.site_get_state() returns jsonb language sql security definer set search_path = public as $$
  select data from public.site_state where id = 1 $$;

create or replace function public.panel_login(p_user text, p_pass text) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare r record; t text;
begin
  select * into r from public.panel_accounts where lower(trim(username)) = lower(trim(p_user)) and password_hash = extensions.crypt(p_pass, password_hash);
  if not found then return null; end if;
  delete from public.panel_sessions where expires_at < now();
  t := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.panel_sessions values (t, r.role, now() + interval '7 days');
  return jsonb_build_object('token', t, 'role', r.role);
end $$;

create or replace function public.panel_role(p_token text) returns text language sql security definer set search_path = public as $$
  select role from public.panel_sessions where token = p_token and expires_at > now() $$;

create or replace function public.panel_accounts_info(p_token text) returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if public.panel_role(p_token) is distinct from 'admin' then raise exception 'forbidden'; end if;
  return (select jsonb_object_agg(role, username) from public.panel_accounts);
end $$;

create or replace function public.site_save_state(p_token text, p_data jsonb) returns boolean language plpgsql security definer set search_path = public as $$
begin
  if public.panel_role(p_token) is null then raise exception 'forbidden'; end if;
  insert into public.site_state(id, data, updated_at) values (1, p_data, now())
  on conflict (id) do update set data = excluded.data, updated_at = now();
  return true;
end $$;

create or replace function public.panel_save_accounts(p_token text, p_admin_user text, p_admin_pass text, p_tattoo_user text, p_tattoo_pass text) returns boolean language plpgsql security definer set search_path = public, extensions as $$
begin
  if public.panel_role(p_token) is distinct from 'admin' then raise exception 'forbidden'; end if;
  if coalesce(trim(p_admin_user),'') = '' or coalesce(trim(p_tattoo_user),'') = '' or lower(trim(p_admin_user)) = lower(trim(p_tattoo_user)) then raise exception 'invalid'; end if;
  update public.panel_accounts set username = trim(p_admin_user) where role = 'admin';
  update public.panel_accounts set username = trim(p_tattoo_user) where role = 'tattoo';
  if coalesce(p_admin_pass,'') <> '' then update public.panel_accounts set password_hash = extensions.crypt(p_admin_pass, extensions.gen_salt('bf')) where role = 'admin'; end if;
  if coalesce(p_tattoo_pass,'') <> '' then
    update public.panel_accounts set password_hash = extensions.crypt(p_tattoo_pass, extensions.gen_salt('bf')) where role = 'tattoo';
    delete from public.panel_sessions where role = 'tattoo';
  end if;
  return true;
end $$;

revoke all on function public.site_get_state(), public.panel_login(text,text), public.panel_role(text), public.panel_accounts_info(text), public.site_save_state(text,jsonb), public.panel_save_accounts(text,text,text,text,text) from public;
grant execute on function public.site_get_state(), public.panel_login(text,text), public.panel_accounts_info(text), public.site_save_state(text,jsonb), public.panel_save_accounts(text,text,text,text,text) to anon, authenticated;