-- VAG Toolbox: private Gruppen und Originalbilder
-- Einmal im Supabase SQL Editor ausführen.
create extension if not exists pgcrypto;

create table if not exists public.photo_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  email text,
  display_name text,
  created_at timestamptz not null default now()
);
create table if not exists public.photo_groups (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 2 and 80),
  owner_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
create table if not exists public.photo_group_members (
  group_id uuid not null references public.photo_groups(id) on delete cascade,
  user_id uuid not null references public.photo_profiles(user_id) on delete cascade,
  role text not null default 'member' check (role in ('owner','admin','member')),
  created_at timestamptz not null default now(),
  primary key(group_id,user_id)
);
create table if not exists public.photo_group_invites (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.photo_groups(id) on delete cascade,
  token text not null unique default encode(gen_random_bytes(24),'hex'),
  created_by uuid not null references auth.users(id) on delete cascade,
  expires_at timestamptz not null default now()+interval '7 days',
  revoked boolean not null default false,
  uses integer not null default 0,
  max_uses integer not null default 100
);
create table if not exists public.photo_group_images (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.photo_groups(id) on delete cascade,
  uploader_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null unique,
  original_name text not null,
  mime_type text not null,
  size_bytes bigint not null check(size_bytes between 1 and 104857600),
  created_at timestamptz not null default now()
);

create or replace function public.photo_is_member(gid uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from photo_group_members where group_id=gid and user_id=auth.uid())
$$;
create or replace function public.photo_is_admin(gid uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from photo_group_members where group_id=gid and user_id=auth.uid() and role in('owner','admin'))
$$;
grant execute on function public.photo_is_member(uuid) to authenticated;
grant execute on function public.photo_is_admin(uuid) to authenticated;

create or replace function public.photo_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
 insert into public.photo_profiles(user_id,email,display_name)
 values(new.id,new.email,coalesce(new.raw_user_meta_data->>'display_name',split_part(new.email,'@',1)))
 on conflict(user_id) do update set email=excluded.email;
 return new;
end $$;
drop trigger if exists photo_new_user_trigger on auth.users;
create trigger photo_new_user_trigger after insert or update of email on auth.users
for each row execute function public.photo_new_user();
insert into public.photo_profiles(user_id,email,display_name)
select id,email,coalesce(raw_user_meta_data->>'display_name',split_part(email,'@',1)) from auth.users
on conflict(user_id) do update set email=excluded.email;

create or replace function public.photo_create_group(group_name text)
returns uuid language plpgsql security definer set search_path=public as $$
declare gid uuid;
begin
 if auth.uid() is null then raise exception 'Anmeldung erforderlich'; end if;
 insert into photo_groups(name,owner_id) values(trim(group_name),auth.uid()) returning id into gid;
 insert into photo_group_members(group_id,user_id,role) values(gid,auth.uid(),'owner');
 return gid;
end $$;

create or replace function public.photo_create_invite(gid uuid)
returns text language plpgsql security definer set search_path=public as $$
declare tok text;
begin
 if not exists(select 1 from photo_group_members where group_id=gid and user_id=auth.uid() and role in('owner','admin'))
 then raise exception 'Keine Berechtigung'; end if;
 insert into photo_group_invites(group_id,created_by) values(gid,auth.uid()) returning token into tok;
 return tok;
end $$;

create or replace function public.photo_join_group(invite_token text)
returns uuid language plpgsql security definer set search_path=public as $$
declare inv photo_group_invites%rowtype;
begin
 select * into inv from photo_group_invites where token=invite_token and not revoked and expires_at>now() and uses<max_uses for update;
 if inv.id is null then raise exception 'Einladung ungültig oder abgelaufen'; end if;
 insert into photo_group_members(group_id,user_id,role) values(inv.group_id,auth.uid(),'member') on conflict do nothing;
 update photo_group_invites set uses=uses+1 where id=inv.id;
 return inv.group_id;
end $$;

grant execute on function public.photo_create_group(text) to authenticated;
grant execute on function public.photo_create_invite(uuid) to authenticated;
grant execute on function public.photo_join_group(text) to authenticated;

alter table photo_profiles enable row level security;
alter table photo_groups enable row level security;
alter table photo_group_members enable row level security;
alter table photo_group_invites enable row level security;
alter table photo_group_images enable row level security;

drop policy if exists photo_groups_read on photo_groups;
create policy photo_groups_read on photo_groups for select to authenticated using(
 public.photo_is_member(id)
);
drop policy if exists photo_members_read on photo_group_members;
create policy photo_members_read on photo_group_members for select to authenticated using(
 public.photo_is_member(photo_group_members.group_id)
);
drop policy if exists photo_profiles_read on photo_profiles;
create policy photo_profiles_read on photo_profiles for select to authenticated using(
 user_id=auth.uid() or exists(
  select 1 from photo_group_members a join photo_group_members b on a.group_id=b.group_id
  where a.user_id=auth.uid() and b.user_id=photo_profiles.user_id
 )
);
drop policy if exists photo_invites_read on photo_group_invites;
create policy photo_invites_read on photo_group_invites for select to authenticated using(
 public.photo_is_admin(photo_group_invites.group_id)
);
drop policy if exists photo_images_read on photo_group_images;
create policy photo_images_read on photo_group_images for select to authenticated using(
 public.photo_is_member(photo_group_images.group_id)
);
drop policy if exists photo_images_insert on photo_group_images;
create policy photo_images_insert on photo_group_images for insert to authenticated with check(
 uploader_id=auth.uid() and public.photo_is_member(photo_group_images.group_id)
);
drop policy if exists photo_images_delete on photo_group_images;
create policy photo_images_delete on photo_group_images for delete to authenticated using(
 uploader_id=auth.uid() or public.photo_is_admin(photo_group_images.group_id)
);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('group-photos','group-photos',false,104857600,array['image/jpeg','image/png','image/webp','image/heic','image/heif','image/tiff'])
on conflict(id) do update set public=false,file_size_limit=104857600,allowed_mime_types=excluded.allowed_mime_types;

drop policy if exists photo_storage_read on storage.objects;
create policy photo_storage_read on storage.objects for select to authenticated using(
 bucket_id='group-photos' and public.photo_is_member((storage.foldername(name))[1]::uuid)
);
drop policy if exists photo_storage_insert on storage.objects;
create policy photo_storage_insert on storage.objects for insert to authenticated with check(
 bucket_id='group-photos' and (storage.foldername(name))[2]=auth.uid()::text and public.photo_is_member((storage.foldername(name))[1]::uuid)
);
drop policy if exists photo_storage_delete on storage.objects;
create policy photo_storage_delete on storage.objects for delete to authenticated using(
 bucket_id='group-photos' and ((storage.foldername(name))[2]=auth.uid()::text or public.photo_is_admin((storage.foldername(name))[1]::uuid))
);