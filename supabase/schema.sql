-- Drop – Datenbank-Schema für Supabase
-- Einmal komplett im SQL Editor ausführen (Run). Kann gefahrlos erneut ausgeführt werden.

-- ============ Tabellen ============

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null default 'Neu bei Drop',
  district text not null default 'Mitte',
  role text not null default 'giver' check (role in ('giver','collector')),
  paypal text not null default '',
  bio text not null default '',
  color text not null default '#1E9E4A',
  created_at timestamptz not null default now()
);

create table if not exists public.listings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  einweg int not null default 0 check (einweg between 0 and 2000),
  mehrweg int not null default 0 check (mehrweg between 0 and 2000),
  kisten int not null default 0 check (kisten between 0 and 200),
  glas int not null default 0 check (glas between 0 and 200),
  glas_fee numeric(5,2) not null default 1 check (glas_fee between 0 and 20),
  photo_url text,
  district text not null,
  lat double precision not null,   -- ungefähre Position (für alle sichtbar)
  lng double precision not null,
  when_label text not null,
  handover text not null default 'persönlich' check (handover in ('persönlich','kontaktlos')),
  payment text not null default 'bar' check (payment in ('bar','paypal')),
  note text not null default '',
  status text not null default 'offen' check (status in ('offen','angenommen','abgeholt','abgeschlossen')),
  collector_id uuid references public.profiles(id) on delete set null,
  owner_rated boolean not null default false,
  collector_rated boolean not null default false,
  paid boolean not null default false
);

-- Genaue Adresse: nur für Abgeber und angenommenen Sammler sichtbar
create table if not exists public.listing_private (
  listing_id uuid primary key references public.listings(id) on delete cascade,
  street text not null,
  lat double precision,
  lng double precision
);

create table if not exists public.messages (
  id bigint generated always as identity primary key,
  listing_id uuid not null references public.listings(id) on delete cascade,
  sender_id uuid references public.profiles(id) on delete set null, -- null = Systemnachricht
  text text not null check (char_length(text) between 1 and 1000),
  created_at timestamptz not null default now()
);

create table if not exists public.ratings (
  id bigint generated always as identity primary key,
  listing_id uuid not null references public.listings(id) on delete cascade,
  from_id uuid not null references public.profiles(id) on delete cascade,
  to_id uuid not null references public.profiles(id) on delete cascade,
  stars int not null check (stars between 1 and 5),
  text text not null default '',
  created_at timestamptz not null default now(),
  unique (listing_id, from_id)
);

create index if not exists listings_status_idx on public.listings(status);
create index if not exists messages_listing_idx on public.messages(listing_id, created_at);
create index if not exists ratings_to_idx on public.ratings(to_id);

-- ============ Profil automatisch bei Registrierung anlegen ============

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  palette text[] := array['#1E9E4A','#0A6CD6','#8E4CC2','#C2571A','#1F8A70','#B23A62','#5B6B12','#3D5A80'];
begin
  insert into public.profiles (id, name, district, role, color)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data->>'name'), ''), 'Neu bei Drop'),
    coalesce(nullif(new.raw_user_meta_data->>'district', ''), 'Mitte'),
    case when new.raw_user_meta_data->>'role' = 'collector' then 'collector' else 'giver' end,
    palette[1 + floor(random() * 8)::int]
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============ Sicherheitsregeln (Row Level Security) ============

alter table public.profiles enable row level security;
alter table public.listings enable row level security;
alter table public.listing_private enable row level security;
alter table public.messages enable row level security;
alter table public.ratings enable row level security;

drop policy if exists "profiles lesen" on public.profiles;
create policy "profiles lesen" on public.profiles for select to authenticated using (true);
drop policy if exists "eigenes profil anlegen" on public.profiles;
create policy "eigenes profil anlegen" on public.profiles for insert to authenticated
  with check (id = auth.uid());
drop policy if exists "eigenes profil ändern" on public.profiles;
create policy "eigenes profil ändern" on public.profiles for update to authenticated
  using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists "anfragen lesen" on public.listings;
create policy "anfragen lesen" on public.listings for select to authenticated using (true);
drop policy if exists "anfrage erstellen" on public.listings;
create policy "anfrage erstellen" on public.listings for insert to authenticated
  with check (owner_id = auth.uid() and status = 'offen' and collector_id is null);
drop policy if exists "offene anfrage löschen" on public.listings;
create policy "offene anfrage löschen" on public.listings for delete to authenticated
  using (owner_id = auth.uid() and status = 'offen');
-- Statuswechsel laufen nur über die Funktionen unten (kein direktes UPDATE).

drop policy if exists "adresse lesen" on public.listing_private;
create policy "adresse lesen" on public.listing_private for select to authenticated
  using (exists (select 1 from public.listings l where l.id = listing_id
                 and (l.owner_id = auth.uid() or l.collector_id = auth.uid())));
drop policy if exists "adresse speichern" on public.listing_private;
create policy "adresse speichern" on public.listing_private for insert to authenticated
  with check (exists (select 1 from public.listings l where l.id = listing_id and l.owner_id = auth.uid()));

drop policy if exists "nachrichten lesen" on public.messages;
create policy "nachrichten lesen" on public.messages for select to authenticated
  using (exists (select 1 from public.listings l where l.id = listing_id
                 and (l.owner_id = auth.uid() or l.collector_id = auth.uid())));
drop policy if exists "nachricht schreiben" on public.messages;
create policy "nachricht schreiben" on public.messages for insert to authenticated
  with check (sender_id = auth.uid() and exists (select 1 from public.listings l where l.id = listing_id
              and l.collector_id is not null and (l.owner_id = auth.uid() or l.collector_id = auth.uid())));

drop policy if exists "bewertungen lesen" on public.ratings;
create policy "bewertungen lesen" on public.ratings for select to authenticated using (true);
-- Bewertungen werden nur über rate_listing() geschrieben.

-- ============ Funktionen für den Ablauf ============

create or replace function public.sys_msg(p_listing uuid, p_text text)
returns void language sql security definer set search_path = public as $$
  insert into public.messages (listing_id, sender_id, text) values (p_listing, null, p_text);
$$;
revoke execute on function public.sys_msg(uuid, text) from public, anon, authenticated;

create or replace function public.accept_listing(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare n text;
begin
  update public.listings set status = 'angenommen', collector_id = auth.uid()
   where id = p_id and status = 'offen' and owner_id <> auth.uid();
  if not found then raise exception 'Diese Anfrage ist nicht mehr offen.'; end if;
  select name into n from public.profiles where id = auth.uid();
  perform public.sys_msg(p_id, n || ' hat die Abholung übernommen.');
end $$;

create or replace function public.release_listing(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare n text;
begin
  update public.listings set status = 'offen', collector_id = null
   where id = p_id and status = 'angenommen' and collector_id = auth.uid();
  if not found then raise exception 'Abholung kann nicht freigegeben werden.'; end if;
  select name into n from public.profiles where id = auth.uid();
  perform public.sys_msg(p_id, n || ' hat die Abholung wieder freigegeben.');
end $$;

create or replace function public.mark_picked(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.listings set status = 'abgeholt'
   where id = p_id and status = 'angenommen' and collector_id = auth.uid();
  if not found then raise exception 'Status kann nicht geändert werden.'; end if;
  perform public.sys_msg(p_id, 'Als abgeholt markiert.');
end $$;

create or replace function public.confirm_done(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.listings set status = 'abgeschlossen', paid = true
   where id = p_id and status = 'abgeholt' and owner_id = auth.uid();
  if not found then raise exception 'Abholung kann nicht bestätigt werden.'; end if;
  perform public.sys_msg(p_id, 'Abholung abgeschlossen.');
end $$;

create or replace function public.rate_listing(p_id uuid, p_stars int, p_text text)
returns void language plpgsql security definer set search_path = public as $$
declare l public.listings;
begin
  select * into l from public.listings where id = p_id;
  if l.id is null or l.status <> 'abgeschlossen' then raise exception 'Noch nicht abgeschlossen.'; end if;
  if auth.uid() = l.owner_id and not l.owner_rated then
    insert into public.ratings (listing_id, from_id, to_id, stars, text)
      values (p_id, auth.uid(), l.collector_id, p_stars, left(coalesce(p_text,''), 500));
    update public.listings set owner_rated = true where id = p_id;
  elsif auth.uid() = l.collector_id and not l.collector_rated then
    insert into public.ratings (listing_id, from_id, to_id, stars, text)
      values (p_id, auth.uid(), l.owner_id, p_stars, left(coalesce(p_text,''), 500));
    update public.listings set collector_rated = true where id = p_id;
  else
    raise exception 'Du hast hier schon bewertet.';
  end if;
end $$;

revoke execute on function public.accept_listing(uuid), public.release_listing(uuid), public.mark_picked(uuid),
  public.confirm_done(uuid), public.rate_listing(uuid, int, text) from public, anon;
grant execute on function public.accept_listing(uuid), public.release_listing(uuid), public.mark_picked(uuid),
  public.confirm_done(uuid), public.rate_listing(uuid, int, text) to authenticated;

-- ============ Foto-Speicher ============

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', true, 3145728, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists "fotos hochladen" on storage.objects;
create policy "fotos hochladen" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- ============ Live-Updates (Realtime) ============

do $$
declare t text;
begin
  foreach t in array array['profiles','listings','listing_private','messages','ratings'] loop
    if not exists (select 1 from pg_publication_tables
                   where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
