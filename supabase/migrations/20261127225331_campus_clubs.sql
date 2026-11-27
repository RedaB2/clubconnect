-- Only verified campus accounts can see the catalog. Listing a club does
-- not grant access to its members, events, conversations or tickets.
create function club_private.club_catalog() returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
    perform club_private.require_usc();
    return (select coalesce(jsonb_agg(jsonb_build_object(
        'club', to_jsonb(b)-'open_enrollment', 'joined', m.id is not null,
        'isAdmin', coalesce(m.admin,false), 'canJoin', b.open_enrollment)
        order by b.name,b.id),'[]'::jsonb)
        from club_private.clubs b left join club_private.members m on
            m.club_id=b.id and m.id=auth.uid()
        where b.open_enrollment or m.id is not null);
end $$;

-- Keep the member's own campus profile when joining a second club. The
-- administrator flag is assigned here, independently of every other membership.
create function club_private.join_additional(c text) returns void
language plpgsql security definer set search_path='' as $$
declare source_profile jsonb;
begin
    perform club_private.require_usc();
    perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
    if exists(select from club_private.members where club_id=c and id=auth.uid()) then return; end if;
    if not exists(select from club_private.clubs where id=c and open_enrollment) then raise exception 'This club is closed to new members.'; end if;
    select to_jsonb(m) into source_profile from club_private.members m where id=auth.uid() order by club_id limit 1;
    if source_profile is null then raise exception 'Complete your campus profile first.'; end if;
    insert into club_private.members select * from jsonb_populate_record(null::club_private.members,
        source_profile || jsonb_build_object('club_id',c,'admin',false));
end $$;

create function club_private.create_club(c uuid, title text, first_profile jsonb default null)
returns void language plpgsql security definer set search_path='' as $$
begin
    perform club_private.require_usc();
    perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
    insert into club_private.clubs(id,name,"fullName",about,"accentHex")
        values(c::text,trim(title),trim(title),'','#974A30') on conflict do nothing;
    if not found then
        -- A network retry for the same creation is safe. An existing club's
        -- identity, settings and roles are never rewritten by this path.
        perform club_private.require_member(c::text,true);
        return;
    end if;
    if first_profile is not null and not exists(select from club_private.members where id=auth.uid()) then
        perform public.enroll_student(c=>c::text, display_name=>first_profile->>'name',
            graduation_term=>first_profile->>'graduationTerm', graduation_year=>(first_profile->>'graduationYear')::integer,
            class_standing=>first_profile->>'classStanding');
    else
        perform club_private.join_additional(c::text);
    end if;
    update club_private.members set admin=true where club_id=c::text and id=auth.uid();
end $$;

-- Serialize decisions about the last organizer, including two simultaneous handoffs.
create function club_private.step_down(c text, successor uuid)
returns void language plpgsql security definer set search_path='' as $$
begin
    perform club_private.require_member(c,true);
    perform from club_private.clubs where id=c for update;
    perform club_private.require_member(c,true);
    if successor is not null then
        if successor=auth.uid() then raise exception 'Choose another member to take over.'; end if;
        update club_private.members set admin=true where club_id=c and id=successor;
        if not found then raise exception 'Choose a current member of this club.'; end if;
    end if;
    if not exists(select from club_private.members where club_id=c and admin and id<>auth.uid()) then
        raise exception 'Choose another organizer before stepping down. You can use member view at any time.';
    end if;
    update club_private.members set admin=false where club_id=c and id=auth.uid();
end $$;

create function public.club_catalog() returns jsonb language sql stable set search_path=''
as $$ select club_private.club_catalog() $$;
create function public.join_additional(c text) returns jsonb language plpgsql set search_path=''
as $$ begin perform club_private.join_additional(c); return club_private.snapshot(c); end $$;
create function public.create_campus_club(c uuid,title text,first_profile jsonb default null) returns jsonb language plpgsql set search_path=''
as $$ begin perform club_private.create_club(c,title,first_profile); return club_private.snapshot(c::text); end $$;
create function public.step_down(c text,successor uuid default null) returns jsonb language plpgsql set search_path=''
as $$ begin perform club_private.step_down(c,successor); return club_private.snapshot(c); end $$;
revoke all on function club_private.club_catalog(), club_private.join_additional(text),club_private.create_club(uuid,text,jsonb),
    club_private.step_down(text,uuid),public.club_catalog(),public.join_additional(text),public.create_campus_club(uuid,text,jsonb),public.step_down(text,uuid)
    from public,anon;
grant execute on function club_private.club_catalog(),club_private.join_additional(text),club_private.create_club(uuid,text,jsonb),
    club_private.step_down(text,uuid),public.club_catalog(),public.join_additional(text),public.create_campus_club(uuid,text,jsonb),public.step_down(text,uuid)
    to authenticated;
