-- Werkstatt Tool: digitale Fahrzeugannahme
-- Nach gruppen-fotos-setup.sql und werkstatt-akten-setup.sql einmalig ausführen.

create table if not exists public.workshop_intakes (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.photo_groups(id) on delete cascade,
  case_id uuid not null references public.workshop_cases(id) on delete cascade,
  mileage integer check(mileage is null or mileage >= 0),
  fuel_level text,
  customer_complaint text,
  handed_over_items text,
  test_drive_allowed boolean not null default false,
  data_processing_accepted boolean not null default false,
  signed_name text not null,
  signature_path text not null,
  created_by uuid not null references public.photo_profiles(user_id),
  created_at timestamptz not null default now()
);
create index if not exists workshop_intakes_case_idx on public.workshop_intakes(case_id,created_at desc);
alter table public.workshop_intakes enable row level security;
drop policy if exists workshop_intakes_read on public.workshop_intakes;
create policy workshop_intakes_read on public.workshop_intakes for select to authenticated
using(public.photo_is_member(group_id));
drop policy if exists workshop_intakes_insert on public.workshop_intakes;
create policy workshop_intakes_insert on public.workshop_intakes for insert to authenticated
with check(created_by=auth.uid() and public.photo_is_member(group_id));
drop policy if exists workshop_intakes_update on public.workshop_intakes;
create policy workshop_intakes_update on public.workshop_intakes for update to authenticated
using(public.photo_is_member(group_id)) with check(public.photo_is_member(group_id));
drop policy if exists workshop_intakes_delete on public.workshop_intakes;
create policy workshop_intakes_delete on public.workshop_intakes for delete to authenticated
using(public.photo_is_admin(group_id));