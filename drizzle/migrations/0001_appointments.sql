create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  client_name text not null,
  phone text not null,
  style text not null default '',
  body_location text not null default '',
  idea text not null default '',
  appointment_date date not null,
  appointment_time text not null,
  status text not null default 'scheduled' check (status in ('scheduled','cancelled')),
  created_at timestamptz not null default now(),
  cancelled_at timestamptz
);
create unique index if not exists appointments_unique_active_slot
  on public.appointments (appointment_date, appointment_time) where status = 'scheduled';
create index if not exists appointments_created_at_idx on public.appointments (created_at desc);
alter table public.appointments enable row level security;
revoke all on public.appointments from anon, authenticated;
grant all on public.appointments to service_role;

create or replace function public.booking_create(
  p_nome text, p_telefone text, p_estilo text, p_local text, p_ideia text, p_data date, p_horario text
) returns jsonb language plpgsql security definer set search_path = public, extensions as $$
declare v_state jsonb; v_row public.appointments;
begin
  if coalesce(trim(p_nome),'') = '' or coalesce(trim(p_telefone),'') = '' or length(regexp_replace(p_telefone, '[^0-9]', '', 'g')) not between 10 and 13 then
    raise exception 'invalid_customer';
  end if;
  if p_data is null or p_data < current_date or coalesce(trim(p_horario),'') = '' then raise exception 'invalid_slot'; end if;
  select data into v_state from public.site_state where id = 1;
  if v_state is null
    or not coalesce(v_state->'dias' @> to_jsonb(extract(dow from p_data)::int), false)
    or not coalesce(v_state->'horas' @> to_jsonb(trim(p_horario)), false)
    or exists (select 1 from jsonb_array_elements(coalesce(v_state->'diasFechados','[]'::jsonb)) x where x->>'data' = p_data::text)
    or coalesce(v_state->'ocupados','[]'::jsonb) @> to_jsonb(p_data::text || ' ' || trim(p_horario))
  then raise exception 'slot_unavailable'; end if;
  insert into public.appointments(client_name,phone,style,body_location,idea,appointment_date,appointment_time)
  values (trim(p_nome), regexp_replace(p_telefone, '[^0-9]', '', 'g'), coalesce(trim(p_estilo),''), coalesce(trim(p_local),''), coalesce(trim(p_ideia),''), p_data, trim(p_horario))
  returning * into v_row;
  return jsonb_build_object('id',v_row.id,'status',v_row.status);
exception when unique_violation then raise exception 'slot_taken';
end $$;

create or replace function public.booking_slots() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('data', appointment_date::text, 'horario', appointment_time)), '[]'::jsonb)
  from public.appointments where status = 'scheduled'
$$;

create or replace function public.booking_list(p_token text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if public.panel_role(p_token) is null then raise exception 'forbidden'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'id',id,'nome',client_name,'telefone',phone,'estilo',style,'local',body_location,'ideia',idea,
    'data',appointment_date::text,'horario',appointment_time,'status',status,
    'criado_em',created_at,'cancelado_em',cancelled_at
  ) order by appointment_date desc, appointment_time desc, created_at desc),'[]'::jsonb) from public.appointments);
end $$;

create or replace function public.booking_cancel(p_token text, p_id uuid) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  if public.panel_role(p_token) is null then raise exception 'forbidden'; end if;
  update public.appointments set status='cancelled', cancelled_at=now()
    where id=p_id and status='scheduled';
  return found;
end $$;

revoke all on function public.booking_create(text,text,text,text,text,date,text), public.booking_slots(), public.booking_list(text), public.booking_cancel(text,uuid) from public;
grant execute on function public.booking_create(text,text,text,text,text,date,text), public.booking_slots() to anon, authenticated;
grant execute on function public.booking_list(text), public.booking_cancel(text,uuid) to anon, authenticated;
