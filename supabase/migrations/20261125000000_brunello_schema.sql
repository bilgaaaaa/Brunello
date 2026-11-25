-- Brunello: one pet, two parents, a shared diary of entries and photos, and the pet's shared expenses.
-- Everything is locked with row level security so only the pet's parents can read or write.

-- ---------- Tables ----------

create table public.pets (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 1 and 20),
  species text not null check (species in ('dog', 'cat')),
  photo_path text,
  currency_code text not null default 'EUR' check (currency_code ~ '^[A-Z]{3}$'),
  invite_code text not null unique,
  created_at timestamptz not null default now()
);

-- A parent is one signed-in person looking after one pet. "nickname" is what the pet calls them.
create table public.parents (
  id uuid primary key default gen_random_uuid(),
  pet_id uuid not null references public.pets (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 12),
  nickname text not null check (char_length(nickname) between 1 and 12),
  created_at timestamptz not null default now(),
  unique (pet_id, user_id),
  unique (id, pet_id)
);

-- One diary line. "detail" says how it went; the allowed values depend on the kind.
create table public.entries (
  id uuid primary key default gen_random_uuid(),
  pet_id uuid not null references public.pets (id) on delete cascade,
  parent_id uuid not null,
  kind text not null,
  detail text,
  photo_path text,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  -- The author must be a parent of this same pet.
  foreign key (parent_id, pet_id) references public.parents (id, pet_id) on delete cascade,
  constraint entries_kind_detail_check check (
    (kind = 'food' and coalesce(detail, '') in ('all', 'half', 'little', 'none'))
    or (kind = 'poo' and coalesce(detail, '') in ('good', 'soft', 'hard', 'runny'))
    or (kind = 'pee' and coalesce(detail, '') in ('normal', 'accident'))
    or (kind in ('walk', 'play') and coalesce(detail, '') in ('short', 'medium', 'long'))
    or (kind = 'health' and coalesce(detail, '') in ('medicine', 'vomit', 'vet', 'unwell'))
    or (kind = 'photo' and detail is null)
  ),
  constraint entries_photo_path_check check ((kind = 'photo') = (photo_path is not null))
);

create index entries_pet_id_occurred_at_idx on public.entries (pet_id, occurred_at desc);
create index entries_parent_id_idx on public.entries (parent_id);
create index parents_user_id_idx on public.parents (user_id);

-- Money spent on the pet. Every expense is shared half and half between the two parents;
-- a "settle_up" row is one parent paying the other back.
create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  pet_id uuid not null references public.pets (id) on delete cascade,
  parent_id uuid not null,
  category text not null check (category in ('food', 'vet', 'medicine', 'grooming', 'toys', 'other', 'settle_up')),
  amount_cents integer not null check (amount_cents between 1 and 10000000),
  spent_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  -- The payer must be a parent of this same pet.
  foreign key (parent_id, pet_id) references public.parents (id, pet_id) on delete cascade
);

create index expenses_pet_id_spent_at_idx on public.expenses (pet_id, spent_at desc);
create index expenses_parent_id_idx on public.expenses (parent_id);

-- Push notification addresses, one row per phone.
create table public.device_tokens (
  token text primary key check (token ~ '^[0-9a-f]{64,200}$'),
  user_id uuid not null references auth.users (id) on delete cascade,
  environment text not null check (environment in ('sandbox', 'production')),
  updated_at timestamptz not null default now()
);

create index device_tokens_user_id_idx on public.device_tokens (user_id);

-- ---------- Helper functions ----------

-- True when the signed-in person is a parent of the given pet. Used by every policy below.
create function public.is_parent_of(target_pet_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.parents
    where parents.pet_id = target_pet_id and parents.user_id = (select auth.uid())
  );
$$;

-- Makes a 6-character invite code without look-alike characters (no I, L, O, 0 or 1).
create function public.generate_invite_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  alphabet constant text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  new_code text;
begin
  loop
    select string_agg(substr(alphabet, 1 + get_byte(uuid_send(gen_random_uuid()), 0) % length(alphabet), 1), '')
      into new_code
      from generate_series(1, 6);
    exit when not exists (select 1 from public.pets where pets.invite_code = new_code);
  end loop;
  return new_code;
end;
$$;

-- ---------- Actions the app calls ----------

-- Creates the pet and makes the caller its first parent.
create function public.create_pet(pet_name text, pet_species text, pet_currency_code text, parent_name text, parent_nickname text)
returns public.pets
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id constant uuid := auth.uid();
  new_pet public.pets;
begin
  if current_user_id is null then
    raise exception 'not_signed_in';
  end if;
  if exists (select 1 from public.parents where parents.user_id = current_user_id) then
    raise exception 'already_in_family';
  end if;

  insert into public.pets (name, species, currency_code, invite_code)
    values (btrim(pet_name), pet_species, upper(pet_currency_code), public.generate_invite_code())
    returning * into new_pet;
  insert into public.parents (pet_id, user_id, name, nickname)
    values (new_pet.id, current_user_id, btrim(parent_name), btrim(parent_nickname));
  return new_pet;
end;
$$;

-- Joins a pet with its invite code. Only two parents fit; the code stops working after that.
create function public.join_pet(code text, parent_name text, parent_nickname text)
returns public.pets
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id constant uuid := auth.uid();
  target_pet public.pets;
begin
  if current_user_id is null then
    raise exception 'not_signed_in';
  end if;

  select * into target_pet from public.pets
    where pets.invite_code = upper(regexp_replace(code, '[^A-Za-z0-9]', '', 'g'))
    for update;
  if not found then
    raise exception 'invite_not_found';
  end if;
  if exists (select 1 from public.parents where parents.pet_id = target_pet.id and parents.user_id = current_user_id) then
    return target_pet;
  end if;
  if exists (select 1 from public.parents where parents.user_id = current_user_id) then
    raise exception 'already_in_family';
  end if;
  if (select count(*) from public.parents where parents.pet_id = target_pet.id) >= 2 then
    raise exception 'family_full';
  end if;

  insert into public.parents (pet_id, user_id, name, nickname)
    values (target_pet.id, current_user_id, btrim(parent_name), btrim(parent_nickname));
  return target_pet;
end;
$$;

-- Remembers this phone's push token for the signed-in person.
create function public.save_device_token(device_token text, device_environment text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not_signed_in';
  end if;
  insert into public.device_tokens (token, user_id, environment)
    values (device_token, auth.uid(), device_environment)
    on conflict (token) do update
      set user_id = excluded.user_id, environment = excluded.environment, updated_at = now();
end;
$$;

-- ---------- Who may do what ----------

alter table public.pets enable row level security;
alter table public.parents enable row level security;
alter table public.entries enable row level security;
alter table public.expenses enable row level security;
alter table public.device_tokens enable row level security;

revoke all on public.pets, public.parents, public.entries, public.expenses, public.device_tokens from anon, authenticated;
grant select on public.pets, public.parents, public.entries, public.expenses to authenticated;
grant update (name, species, photo_path, currency_code) on public.pets to authenticated;
grant update (name, nickname) on public.parents to authenticated;
grant insert, delete on public.entries, public.expenses to authenticated;

revoke execute on function public.is_parent_of(uuid) from public, anon;
revoke execute on function public.generate_invite_code() from public, anon, authenticated;
revoke execute on function public.create_pet(text, text, text, text, text) from public, anon;
revoke execute on function public.join_pet(text, text, text) from public, anon;
revoke execute on function public.save_device_token(text, text) from public, anon;
grant execute on function public.is_parent_of(uuid) to authenticated;
grant execute on function public.create_pet(text, text, text, text, text) to authenticated;
grant execute on function public.join_pet(text, text, text) to authenticated;
grant execute on function public.save_device_token(text, text) to authenticated;

create policy "Parents can see their pet" on public.pets
  for select to authenticated using (public.is_parent_of(id));
create policy "Parents can edit their pet" on public.pets
  for update to authenticated using (public.is_parent_of(id)) with check (public.is_parent_of(id));

create policy "Parents can see both parents" on public.parents
  for select to authenticated using (public.is_parent_of(pet_id));
create policy "Parents can edit their own name" on public.parents
  for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "Parents can read the diary" on public.entries
  for select to authenticated using (public.is_parent_of(pet_id));
create policy "Parents can add their own entries" on public.entries
  for insert to authenticated with check (
    exists (
      select 1 from public.parents
      where parents.id = entries.parent_id and parents.pet_id = entries.pet_id and parents.user_id = (select auth.uid())
    )
  );
create policy "Parents can delete their own entries" on public.entries
  for delete to authenticated using (
    exists (
      select 1 from public.parents
      where parents.id = entries.parent_id and parents.user_id = (select auth.uid())
    )
  );

create policy "Parents can read the expenses" on public.expenses
  for select to authenticated using (public.is_parent_of(pet_id));
create policy "Parents can add what they paid" on public.expenses
  for insert to authenticated with check (
    exists (
      select 1 from public.parents
      where parents.id = expenses.parent_id and parents.pet_id = expenses.pet_id and parents.user_id = (select auth.uid())
    )
  );
create policy "Parents can delete what they added" on public.expenses
  for delete to authenticated using (
    exists (
      select 1 from public.parents
      where parents.id = expenses.parent_id and parents.user_id = (select auth.uid())
    )
  );

-- ---------- Live updates ----------

alter publication supabase_realtime add table public.entries, public.expenses, public.parents, public.pets;

-- ---------- Photos ----------
-- Private bucket; every file lives in a folder named after the pet's id.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('photos', 'photos', false, 5242880, array['image/jpeg'])
  on conflict (id) do nothing;

create policy "Parents can view their pet's photos" on storage.objects
  for select to authenticated using (
    bucket_id = 'photos' and public.is_parent_of(((storage.foldername(name))[1])::uuid)
  );
create policy "Parents can add photos of their pet" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'photos' and public.is_parent_of(((storage.foldername(name))[1])::uuid)
  );
create policy "Parents can delete their own photos" on storage.objects
  for delete to authenticated using (
    bucket_id = 'photos' and owner_id = (select auth.uid())::text
  );
