-- Werkstatt Tool: Erweiterung um gemeinsame Fahrzeugakten
-- Nach gruppen-fotos-setup.sql einmalig im Supabase SQL Editor ausführen.

create table if not exists public.workshop_cases (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.photo_groups(id) on delete cascade,
  plate text,
  vin text,
  vehicle text,
  customer_name text,
  mileage integer check (mileage is null or mileage >= 0),
  status text not null default 'open' check (status in ('open','in_progress','waiting','ready','closed')),
  notes text,
  created_by uuid not null references public.photo_profiles(user_id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (nullif(trim(coalesce(plate,'')),'') is not null or nullif(trim(coalesce(vin,'')),'') is not null)
);

create table if not exists public.workshop_case_files (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.workshop_cases(id) on delete cascade,
  group_id uuid not null references public.photo_groups(id) on delete cascade,
  uploader_id uuid not null references public.photo_profiles(user_id),
  storage_path text not null unique,
  original_name text not null,
  mime_type text,
  size_bytes bigint not null check(size_bytes between 1 and 104857600),
  category text not null default 'other' check(category in ('handover','damage','work','new_part','vcds','document','other')),
  note text,
  created_at timestamptz not null default now()
);

create index if not exists workshop_cases_group_updated_idx on public.workshop_cases(group_id,updated_at desc);
create index if not exists workshop_cases_plate_idx on public.workshop_cases(upper(plate));
create index if not exists workshop_cases_vin_idx on public.workshop_cases(upper(vin));
create index if not exists workshop_case_files_case_idx on public.workshop_case_files(case_id,created_at desc);

create or replace function public.workshop_touch_case()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 new.updated_at=now();
 return new;
end $$;
drop trigger if exists workshop_touch_case_trigger on public.workshop_cases;
create trigger workshop_touch_case_trigger before update on public.workshop_cases
for each row execute function public.workshop_touch_case();

alter table public.workshop_cases enable row level security;
alter table public.workshop_case_files enable row level security;

drop policy if exists workshop_cases_read on public.workshop_cases;
create policy workshop_cases_read on public.workshop_cases for select to authenticated
using(public.photo_is_member(group_id));
drop policy if exists workshop_cases_insert on public.workshop_cases;
create policy workshop_cases_insert on public.workshop_cases for insert to authenticated
with check(created_by=auth.uid() and public.photo_is_member(group_id));
drop policy if exists workshop_cases_update on public.workshop_cases;
create policy workshop_cases_update on public.workshop_cases for update to authenticated
using(public.photo_is_member(group_id)) with check(public.photo_is_member(group_id));
drop policy if exists workshop_cases_delete on public.workshop_cases;
create policy workshop_cases_delete on public.workshop_cases for delete to authenticated
using(public.photo_is_admin(group_id));

drop policy if exists workshop_files_read on public.workshop_case_files;
create policy workshop_files_read on public.workshop_case_files for select to authenticated
using(public.photo_is_member(group_id));
drop policy if exists workshop_files_insert on public.workshop_case_files;
create policy workshop_files_insert on public.workshop_case_files for insert to authenticated
with check(uploader_id=auth.uid() and public.photo_is_member(group_id));
drop policy if exists workshop_files_update on public.workshop_case_files;
create policy workshop_files_update on public.workshop_case_files for update to authenticated
using(uploader_id=auth.uid() or public.photo_is_admin(group_id));
drop policy if exists workshop_files_delete on public.workshop_case_files;
create policy workshop_files_delete on public.workshop_case_files for delete to authenticated
using(uploader_id=auth.uid() or public.photo_is_admin(group_id));

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('workshop-files','workshop-files',false,104857600,null)
on conflict(id) do update set public=false,file_size_limit=104857600,allowed_mime_types=null;

drop policy if exists workshop_storage_read on storage.objects;
create policy workshop_storage_read on storage.objects for select to authenticated
using(bucket_id='workshop-files' and public.photo_is_member((storage.foldername(name))[1]::uuid));

drop policy if exists workshop_storage_insert on storage.objects;
create policy workshop_storage_insert on storage.objects for insert to authenticated
with check(
 bucket_id='workshop-files'
 and (storage.foldername(name))[3]=auth.uid()::text
 and public.photo_is_member((storage.foldername(name))[1]::uuid)
);

drop policy if exists workshop_storage_delete on storage.objects;
create policy workshop_storage_delete on storage.objects for delete to authenticated
using(
 bucket_id='workshop-files'
 and ((storage.foldername(name))[3]=auth.uid()::text or public.photo_is_admin((storage.foldername(name))[1]::uuid))
);