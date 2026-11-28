-- Tables live outside PostgREST's exposed schemas. Each entry point binds its
-- operations to auth.uid(); the app never supplies a user ID for a write.
create schema club_private;
revoke all on schema club_private from public, anon;
grant usage on schema club_private to authenticated;

create table club_private.clubs (
    id text primary key,
    name text not null check (length(trim(name)) between 1 and 60),
    "fullName" text not null check (length(trim("fullName")) between 1 and 160),
    about text not null check (length(about) <= 4000),
    "accentHex" text not null check ("accentHex" ~ '^#[0-9a-fA-F]{6}$'),
    "logoData" text check (length("logoData") <= 160000),
    open_enrollment boolean not null default true
);
create table club_private.members (
    club_id text references club_private.clubs on delete cascade,
    id uuid references auth.users on delete cascade,
    name text not null check (length(trim(name)) between 1 and 100),
    kind text not null default 'student' check (kind in ('student','alumni')),
    major text not null default '' check (length(major) <= 200),
    interests text[] not null default '{}' check (cardinality(interests) <= 40 and length(interests::text) <= 3000),
    experience text not null default '' check (length(experience) <= 4000),
    bio text not null default '' check (length(bio) <= 4000),
    "photoData" text check (length("photoData") <= 160000),
    admin boolean not null default false,
    primary key (club_id, id)
);
create table club_private.events (
    id uuid primary key,
    club_id text not null references club_private.clubs on delete cascade,
    title text not null check (length(trim(title)) between 1 and 160),
    summary text not null check (length(summary) <= 6000),
    location text not null check (length(trim(location)) between 1 and 300),
    "startsAt" timestamptz not null,
    "endsAt" timestamptz not null check ("endsAt" > "startsAt"),
    category text not null check (length(category) between 1 and 80),
    unique (club_id, id)
);
create table club_private.tickets (
    id uuid primary key default gen_random_uuid(),
    club_id text not null,
    "eventID" uuid not null,
    owner uuid not null,
    code text unique not null default upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 16)),
    "checkedIn" boolean not null default false,
    foreign key (club_id, "eventID") references club_private.events(club_id,id) on delete cascade,
    foreign key (club_id, owner) references club_private.members(club_id,id) on delete cascade,
    unique ("eventID", owner)
);
create index member_identity on club_private.members(id);
create index ticket_owner on club_private.tickets(club_id,owner);
create table club_private.organizer_invites (
    digest bytea primary key,
    club_id text not null references club_private.clubs on delete cascade
);
alter table club_private.clubs enable row level security;
alter table club_private.members enable row level security;
alter table club_private.events enable row level security;
alter table club_private.tickets enable row level security;
alter table club_private.organizer_invites enable row level security;
revoke all on all tables in schema club_private from public, anon, authenticated;
insert into club_private.clubs (id,name,"fullName",about,"accentHex") values
('menasa','MENASA','Middle Eastern and North African Association',
'A campus community for Middle Eastern and North African students, alumni, and friends.','#974A30');

create function club_private.require_member(c text, organizer boolean default false)
returns void language plpgsql stable security definer set search_path='' as $$
begin
    if not exists (select from club_private.members where club_id=c and id=(select auth.uid()) and (not organizer or admin)) then
        raise exception 'Club membership or organizer access required.' using errcode='42501';
    end if;
end $$;

create function club_private.snapshot(c text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
    perform club_private.require_member(c);
    select jsonb_build_object(
        'club', (select to_jsonb(b)-'open_enrollment' from club_private.clubs b where id=c),
        'members', coalesce((select jsonb_agg(to_jsonb(m)-'club_id'-'admin' order by m.name) from club_private.members m where club_id=c), '[]'),
        'events', coalesce((select jsonb_agg(to_jsonb(e)-'club_id' order by e."startsAt") from club_private.events e where club_id=c), '[]'),
        'tickets', coalesce((select jsonb_agg(to_jsonb(t)-'club_id'-'owner') from club_private.tickets t where club_id=c and owner=(select auth.uid())), '[]'),
        'myID', auth.uid(), 'isAdmin', (select admin from club_private.members where club_id=c and id=(select auth.uid()))
    ) into result;
    return result;
end $$;

create function club_private.enroll(c text, display_name text)
returns void language plpgsql security definer set search_path='' as $$
begin
    if auth.uid() is null then raise exception 'Sign in to join.' using errcode='42501'; end if;
    if not exists (select from club_private.clubs where id=c and open_enrollment) then raise exception 'Enrollment is closed.'; end if;
    insert into club_private.members(club_id,id,name) values(c,auth.uid(),trim(display_name)) on conflict do nothing;
end $$;

create function club_private.save_profile(c text, entry jsonb)
returns void language plpgsql security definer set search_path='' as $$
begin
    perform club_private.require_member(c);
    update club_private.members set name=trim(entry->>'name'), kind=entry->>'kind', major=entry->>'major',
        interests=array(select jsonb_array_elements_text(entry->'interests')), experience=entry->>'experience',
        bio=entry->>'bio', "photoData"=entry->>'photoData'
    where club_id=c and id=auth.uid();
end $$;

create function club_private.save_club(c text, entry jsonb)
returns void language plpgsql security definer set search_path='' as $$
begin
    perform club_private.require_member(c,true);
    update club_private.clubs set name=trim(entry->>'name'), "fullName"=trim(entry->>'fullName'), about=entry->>'about',
        "accentHex"=entry->>'accentHex', "logoData"=entry->>'logoData' where id=c;
end $$;

create function club_private.save_event(c text, entry jsonb)
returns void language plpgsql security definer set search_path='' as $$
begin
    perform club_private.require_member(c,true);
    insert into club_private.events as existing(id,club_id,title,summary,location,"startsAt","endsAt",category)
    values((entry->>'id')::uuid,c,trim(entry->>'title'),entry->>'summary',trim(entry->>'location'),
        (entry->>'startsAt')::timestamptz,(entry->>'endsAt')::timestamptz,entry->>'category')
    on conflict (id) do update set title=excluded.title,summary=excluded.summary,location=excluded.location,
        "startsAt"=excluded."startsAt","endsAt"=excluded."endsAt",category=excluded.category where existing.club_id=c;
    if not found then raise exception 'Event unavailable.'; end if;
end $$;

create function club_private.rsvp(c text, eid uuid, attending boolean)
returns void language plpgsql security definer set search_path='' as $$
declare finish timestamptz;
begin
    perform club_private.require_member(c);
    select "endsAt" into finish from club_private.events where id=eid and club_id=c;
    if finish is null or finish<=now() then raise exception 'This event is closed.'; end if;
    if attending then
        insert into club_private.tickets (club_id,"eventID",owner) values (c,eid,auth.uid()) on conflict ("eventID",owner) do nothing;
    else
        perform from club_private.tickets where "eventID"=eid and owner=auth.uid() and club_id=c for update;
        if exists(select from club_private.tickets where "eventID"=eid and owner=auth.uid() and "checkedIn") then
            raise exception 'This ticket has already been checked in.';
        end if;
        delete from club_private.tickets where "eventID"=eid and owner=auth.uid() and club_id=c;
    end if;
end $$;

create function club_private.check_in(c text, eid uuid, ticket_code text)
returns text language plpgsql security definer set search_path='' as $$
declare attendee uuid;
begin
    perform club_private.require_member(c,true);
    update club_private.tickets set "checkedIn"=true where club_id=c and "eventID"=eid and code=upper(trim(ticket_code))
        and not "checkedIn" returning owner into attendee;
    if attendee is null then
        if exists(select from club_private.tickets where club_id=c and "eventID"=eid and code=upper(trim(ticket_code))) then
            raise exception 'This ticket has already been checked in.';
        end if;
        raise exception 'No matching ticket for this event.';
    end if;
    return (select name from club_private.members where club_id=c and id=attendee);
end $$;

create function club_private.claim_organizer(c text, invite text)
returns void language plpgsql security definer set search_path='' as $$
begin
    perform club_private.require_member(c);
    delete from club_private.organizer_invites where club_id=c and digest=sha256(convert_to(trim(invite),'UTF8'));
    if not found then raise exception 'This organizer invitation is invalid or already used.'; end if;
    update club_private.members set admin=true where club_id=c and id=auth.uid();
end $$;

-- PostgREST wrappers use invoker rights. The private functions enforce the
-- same checks even if called without a wrapper. Each write returns fresh state.
create function public.snapshot(c text default 'menasa') returns jsonb language sql stable set search_path=''
as $$ select club_private.snapshot(c) $$;
create function public.join_club(display_name text,c text default 'menasa') returns jsonb language plpgsql set search_path=''
as $$ begin perform club_private.enroll(c,display_name); return club_private.snapshot(c); end $$;
create function public.save_profile(entry jsonb,c text default 'menasa') returns jsonb language plpgsql set search_path=''
as $$ begin perform club_private.save_profile(c,entry); return club_private.snapshot(c); end $$;
create function public.save_club(entry jsonb,c text default 'menasa') returns jsonb language plpgsql set search_path=''
as $$ begin perform club_private.save_club(c,entry); return club_private.snapshot(c); end $$;
create function public.save_event(entry jsonb,c text default 'menasa') returns jsonb language plpgsql set search_path=''
as $$ begin perform club_private.save_event(c,entry); return club_private.snapshot(c); end $$;
create function public.set_rsvp(eid uuid,attending boolean,c text default 'menasa') returns jsonb language plpgsql set search_path=''
as $$ begin perform club_private.rsvp(c,eid,attending); return club_private.snapshot(c); end $$;
create function public.check_in(eid uuid,ticket_code text,c text default 'menasa') returns text language sql set search_path=''
as $$ select club_private.check_in(c,eid,ticket_code) $$;
create function public.claim_organizer(invite text,c text default 'menasa') returns jsonb language plpgsql set search_path=''
as $$ begin perform club_private.claim_organizer(c,invite); return club_private.snapshot(c); end $$;

revoke all on all functions in schema club_private from public, anon;
grant execute on all functions in schema club_private to authenticated;
do $$
declare fn regprocedure;
begin
    foreach fn in array array['public.snapshot(text)'::regprocedure,'public.join_club(text,text)'::regprocedure,
      'public.save_profile(jsonb,text)'::regprocedure,'public.save_club(jsonb,text)'::regprocedure,
      'public.save_event(jsonb,text)'::regprocedure,'public.set_rsvp(uuid,boolean,text)'::regprocedure,
      'public.check_in(uuid,text,text)'::regprocedure,'public.claim_organizer(text,text)'::regprocedure] loop
        execute format('revoke all on function %s from public, anon',fn);
        execute format('grant execute on function %s to authenticated',fn);
    end loop;
end $$;
