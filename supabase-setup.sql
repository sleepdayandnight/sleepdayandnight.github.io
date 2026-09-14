create extension if not exists pgcrypto;

create table if not exists public.rooms (
  id text primary key,
  active_question integer not null default 0 check (active_question between 0 and 4),
  created_at timestamptz not null default now()
);

create table if not exists public.players (
  room_id text not null references public.rooms(id) on delete cascade,
  client_id text not null,
  nickname text not null check (char_length(nickname) between 1 and 10),
  team integer not null check (team between 0 and 4),
  joined_at timestamptz not null default now(),
  primary key (room_id, client_id)
);

create table if not exists public.notes (
  id uuid primary key default gen_random_uuid(),
  room_id text not null references public.rooms(id) on delete cascade,
  client_id text not null,
  question integer not null check (question between 0 and 4),
  body text not null check (char_length(body) between 1 and 60),
  likes integer not null default 0,
  liked_by text[] not null default '{}',
  created_at timestamptz not null default now()
);

alter table public.rooms enable row level security;
alter table public.players enable row level security;
alter table public.notes enable row level security;

drop policy if exists "event room read" on public.rooms;
drop policy if exists "event room create" on public.rooms;
drop policy if exists "event room update" on public.rooms;
drop policy if exists "event players read" on public.players;
drop policy if exists "event notes read" on public.notes;
drop policy if exists "event notes insert" on public.notes;

create policy "event room read" on public.rooms for select using (true);
create policy "event room create" on public.rooms for insert with check (true);
create policy "event room update" on public.rooms for update using (true) with check (true);
create policy "event players read" on public.players for select using (true);
create policy "event notes read" on public.notes for select using (true);
create policy "event notes insert" on public.notes for insert with check (true);

create or replace function public.assign_team(p_room_id text, p_client_id text, p_nickname text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  selected_team integer;
begin
  perform pg_advisory_xact_lock(hashtext(p_room_id));
  insert into rooms (id) values (p_room_id) on conflict (id) do nothing;
  select team into selected_team from players where room_id = p_room_id and client_id = p_client_id;
  if selected_team is not null then return selected_team; end if;
  select candidate.team into selected_team
  from generate_series(0, 4) as candidate(team)
  left join players on players.room_id = p_room_id and players.team = candidate.team
  group by candidate.team
  having count(players.client_id) < 6
  order by count(players.client_id), random()
  limit 1;
  if selected_team is null then raise exception 'All teams are full'; end if;
  insert into players (room_id, client_id, nickname, team) values (p_room_id, p_client_id, left(trim(p_nickname), 10), selected_team);
  return selected_team;
end;
$$;

create or replace function public.like_note(p_note_id uuid, p_client_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update notes
  set likes = likes + 1, liked_by = array_append(liked_by, p_client_id)
  where id = p_note_id and not (p_client_id = any(liked_by));
end;
$$;

grant execute on function public.assign_team(text, text, text) to anon, authenticated;
grant execute on function public.like_note(uuid, text) to anon, authenticated;

do $$
begin
  begin alter publication supabase_realtime add table public.rooms; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.players; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.notes; exception when duplicate_object then null; end;
end $$;
