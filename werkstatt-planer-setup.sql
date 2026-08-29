-- Werkstatt Tool: gemeinsamer Werkstattplaner
-- Nach gruppen-fotos-setup.sql und werkstatt-akten-setup.sql einmalig ausführen.

create table if not exists public.workshop_appointments (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.photo_groups(id) on delete cascade,
  case_id uuid references public.workshop_cases(id) on delete set null,
  plate text,
  vin text,
  vehicle text,
  customer_name text,
  reason text not null,
  notes text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'planned'
    check (status in ('planned','arrived','in_progress','done','cancelled')),
  created_by uuid not null references public.photo_profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create index if not exists workshop_appointments_group_start_idx
  on public.workshop_appointments(group_id,starts_at);
create index if not exists workshop_appointments_plate_idx
  on public.workshop_appointments(group_id,upper(plate));

create or replace function public.workshop_touch_appointment()
returns trigger language plpgsql security definer set search_path=public as $$
begin
  new.updated_at=now();
  return new;
end $$;

drop trigger if exists workshop_touch_appointment_trigger on public.workshop_appointments;
create trigger workshop_touch_appointment_trigger
before update on public.workshop_appointments
for each row execute function public.workshop_touch_appointment();

alter table public.workshop_appointments enable row level security;

drop policy if exists workshop_appointments_read on public.workshop_appointments;
create policy workshop_appointments_read on public.workshop_appointments
for select to authenticated using(public.photo_is_member(group_id));

drop policy if exists workshop_appointments_insert on public.workshop_appointments;
create policy workshop_appointments_insert on public.workshop_appointments
for insert to authenticated
with check(created_by=auth.uid() and public.photo_is_member(group_id));

drop policy if exists workshop_appointments_update on public.workshop_appointments;
create policy workshop_appointments_update on public.workshop_appointments
for update to authenticated
using(public.photo_is_member(group_id))
with check(public.photo_is_member(group_id));

drop policy if exists workshop_appointments_delete on public.workshop_appointments;
create policy workshop_appointments_delete on public.workshop_appointments
for delete to authenticated
using(public.photo_is_admin(group_id));
