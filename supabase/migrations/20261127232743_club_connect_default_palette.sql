alter table club_private.clubs
    alter column "accentHex" set default '#80523F',
    alter column "secondaryHex" set default '#F0E4D9';

create or replace function club_private.create_club(c uuid, title text, first_profile jsonb default null)
returns void language plpgsql security definer set search_path='' as $$
begin
    perform club_private.require_usc();
    perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
    insert into club_private.clubs(id,name,"fullName",about)
        values(c::text,trim(title),trim(title),'') on conflict do nothing;
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
