create extension if not exists pgcrypto;

create table if not exists public.rooms (
  id text primary key,
  active_question integer not null default 0 check (active_question between 0 and 4),
  mission_active boolean not null default false,
  mission_started_at timestamptz,
  mission_deadline timestamptz,
  created_at timestamptz not null default now()
);

alter table public.rooms add column if not exists mission_active boolean not null default false;
alter table public.rooms add column if not exists mission_started_at timestamptz;
alter table public.rooms add column if not exists mission_deadline timestamptz;

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

create table if not exists public.participant_cards (
  room_id text not null references public.rooms(id) on delete cascade,
  client_id text not null,
  card_code text not null,
  token_hash text not null,
  created_at timestamptz not null default now(),
  primary key (room_id, client_id),
  unique (room_id, card_code)
);

create table if not exists public.task_requests (
  id uuid primary key default gen_random_uuid(),
  room_id text not null references public.rooms(id) on delete cascade,
  request_code text not null,
  initiator_client_id text not null,
  task_index integer not null check (task_index between 0 and 9),
  expires_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending', 'confirmed', 'expired', 'cancelled')),
  created_at timestamptz not null default now(),
  unique (room_id, request_code)
);

create table if not exists public.task_claims (
  id uuid primary key default gen_random_uuid(),
  room_id text not null references public.rooms(id) on delete cascade,
  task_index integer not null check (task_index between 0 and 9),
  initiator_client_id text not null,
  verifier_client_id text not null,
  initiator_code text not null,
  verifier_code text not null,
  created_at timestamptz not null default now(),
  unique (room_id, initiator_client_id, task_index),
  unique (room_id, initiator_client_id, verifier_client_id),
  check (initiator_client_id <> verifier_client_id)
);

alter table public.rooms enable row level security;
alter table public.players enable row level security;
alter table public.notes enable row level security;
alter table public.participant_cards enable row level security;
alter table public.task_requests enable row level security;
alter table public.task_claims enable row level security;

drop policy if exists "event room read" on public.rooms;
drop policy if exists "event room create" on public.rooms;
drop policy if exists "event room update" on public.rooms;
drop policy if exists "event players read" on public.players;
drop policy if exists "event notes read" on public.notes;
drop policy if exists "event notes insert" on public.notes;
drop policy if exists "event task claims read" on public.task_claims;

create policy "event room read" on public.rooms for select using (true);
create policy "event room create" on public.rooms for insert with check (true);
create policy "event room update" on public.rooms for update using (true) with check (true);
create policy "event players read" on public.players for select using (true);
create policy "event notes read" on public.notes for select using (true);
create policy "event notes insert" on public.notes for insert with check (true);
create policy "event task claims read" on public.task_claims for select using (true);

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

create or replace function public.ensure_participant_card(p_room_id text, p_client_id text, p_token text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  existing_code text;
  candidate_code text;
begin
  if coalesce(length(trim(p_token)), 0) < 20 then raise exception 'Invalid participant credential'; end if;
  if not exists (select 1 from players where room_id = p_room_id and client_id = p_client_id) then
    raise exception 'Join the room before creating an identity card';
  end if;
  select card_code into existing_code
  from participant_cards
  where room_id = p_room_id and client_id = p_client_id
    and token_hash = encode(digest(p_token, 'sha256'), 'hex');
  if existing_code is not null then return existing_code; end if;
  if exists (select 1 from participant_cards where room_id = p_room_id and client_id = p_client_id) then
    raise exception 'This participant already has another identity card';
  end if;
  loop
    candidate_code := upper(substr(encode(gen_random_bytes(4), 'hex'), 1, 6));
    exit when not exists (select 1 from participant_cards where room_id = p_room_id and card_code = candidate_code);
  end loop;
  insert into participant_cards (room_id, client_id, card_code, token_hash)
  values (p_room_id, p_client_id, candidate_code, encode(digest(p_token, 'sha256'), 'hex'));
  return candidate_code;
end;
$$;

create or replace function public.create_task_request(p_room_id text, p_client_id text, p_token text, p_task_index integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  room_row rooms%rowtype;
  request_code text;
  expires_at_value timestamptz;
begin
  if p_task_index < 0 or p_task_index > 9 then raise exception 'Unknown task'; end if;
  select * into room_row from rooms where id = p_room_id;
  if room_row.id is null or not room_row.mission_active or room_row.mission_deadline is null or room_row.mission_deadline <= now() then
    raise exception 'Mission is not accepting verifications';
  end if;
  if not exists (select 1 from participant_cards where room_id = p_room_id and client_id = p_client_id and token_hash = encode(digest(p_token, 'sha256'), 'hex')) then
    raise exception 'Invalid participant credential';
  end if;
  if not exists (select 1 from players where room_id = p_room_id and client_id = p_client_id) then raise exception 'Participant not found'; end if;
  if exists (select 1 from task_claims where room_id = p_room_id and initiator_client_id = p_client_id and task_index = p_task_index) then
    raise exception 'This task is already verified';
  end if;
  loop
    request_code := lpad((floor(random() * 1000000))::integer::text, 6, '0');
    exit when not exists (select 1 from task_requests tr where tr.room_id = p_room_id and tr.request_code = request_code and tr.status = 'pending');
  end loop;
  expires_at_value := least(room_row.mission_deadline, now() + interval '3 minutes');
  insert into task_requests (room_id, request_code, initiator_client_id, task_index, expires_at)
  values (p_room_id, request_code, p_client_id, p_task_index, expires_at_value);
  return jsonb_build_object('request_code', request_code, 'task_index', p_task_index, 'expires_at', expires_at_value);
end;
$$;

create or replace function public.confirm_task_request(p_room_id text, p_verifier_client_id text, p_token text, p_request_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row task_requests%rowtype;
  initiator_code_value text;
  verifier_code_value text;
begin
  if not exists (select 1 from participant_cards where room_id = p_room_id and client_id = p_verifier_client_id and token_hash = encode(digest(p_token, 'sha256'), 'hex')) then
    raise exception 'Invalid participant credential';
  end if;
  select * into request_row
  from task_requests
  where room_id = p_room_id and request_code = trim(p_request_code) and status = 'pending'
  for update;
  if request_row.id is null then raise exception '核验码不存在或已使用'; end if;
  if request_row.expires_at <= now() then
    update task_requests set status = 'expired' where id = request_row.id;
    raise exception '核验码已过期';
  end if;
  if request_row.initiator_client_id = p_verifier_client_id then raise exception '不能确认自己的任务'; end if;
  if not exists (select 1 from players where room_id = p_room_id and client_id = request_row.initiator_client_id) then raise exception '任务发起人已离开房间'; end if;
  if exists (select 1 from task_claims where room_id = p_room_id and initiator_client_id = request_row.initiator_client_id and task_index = request_row.task_index) then
    update task_requests set status = 'confirmed' where id = request_row.id;
    raise exception '该任务已经被确认';
  end if;
  if exists (select 1 from task_claims where room_id = p_room_id and initiator_client_id = request_row.initiator_client_id and verifier_client_id = p_verifier_client_id) then
    raise exception '同一伙伴只能确认该同学的一项任务';
  end if;
  select card_code into initiator_code_value from participant_cards where room_id = p_room_id and client_id = request_row.initiator_client_id;
  select card_code into verifier_code_value from participant_cards where room_id = p_room_id and client_id = p_verifier_client_id;
  insert into task_claims (room_id, task_index, initiator_client_id, verifier_client_id, initiator_code, verifier_code)
  values (p_room_id, request_row.task_index, request_row.initiator_client_id, p_verifier_client_id, initiator_code_value, verifier_code_value);
  update task_requests set status = 'confirmed' where id = request_row.id;
  return jsonb_build_object('task_index', request_row.task_index, 'initiator_code', initiator_code_value, 'verifier_code', verifier_code_value);
end;
$$;

grant execute on function public.assign_team(text, text, text) to anon, authenticated;
grant execute on function public.like_note(uuid, text) to anon, authenticated;
grant execute on function public.ensure_participant_card(text, text, text) to anon, authenticated;
grant execute on function public.create_task_request(text, text, text, integer) to anon, authenticated;
grant execute on function public.confirm_task_request(text, text, text, text) to anon, authenticated;

do $$
begin
  begin alter publication supabase_realtime add table public.rooms; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.players; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.notes; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.task_claims; exception when duplicate_object then null; end;
end $$;
