-- Existing members keep their historical profile and fill in these fields at next enrollment.
alter table club_private.members
    add column "graduationTerm" text check ("graduationTerm" in ('spring', 'fall')),
    add column "graduationYear" integer check ("graduationYear" between 1900 and 2200),
    add column "classStanding" text check ("classStanding" in ('freshman','sophomore','junior','senior','graduate')),
    add constraint graduation_pair check (
        ("graduationTerm" is null) = ("graduationYear" is null)
        and ("graduationTerm" is not null or "classStanding" is null)
    );

create function club_private.graduation_kind(term text, yr integer,
    on_date date default (now() at time zone 'America/Los_Angeles')::date)
returns text language sql immutable strict set search_path='' as $$
    select case when on_date < case term
        when 'spring' then make_date(yr, 6, 1)
        when 'fall' then make_date(yr + 1, 1, 1)
    end then 'student' else 'alumni' end
$$;

create function club_private.validate_graduation(term text, yr integer, standing text)
returns text language plpgsql stable set search_path='' as $$
declare membership text;
begin
    if term is null or term not in ('spring','fall')
       or yr is null or yr not between 1900 and extract(year from now() at time zone 'America/Los_Angeles')::integer + 12 then
        raise exception 'Choose a graduation term and valid graduation year.' using errcode='22023';
    end if;
    membership := club_private.graduation_kind(term, yr);
    if membership = 'student' and (standing is null or standing not in ('freshman','sophomore','junior','senior','graduate')) then
        raise exception 'Choose your current class standing.' using errcode='22023';
    end if;
    return membership;
end $$;

create function club_private.enroll_student(c text, display_name text, graduation_term text,
    graduation_year integer, class_standing text)
returns void language plpgsql security definer set search_path='' as $$
declare
    member_id uuid := auth.uid();
    membership text;
    previous club_private.members%rowtype;
begin
    perform club_private.require_usc();
    perform pg_advisory_xact_lock(hashtextextended(member_id::text,0));
    membership := club_private.validate_graduation(graduation_term, graduation_year, class_standing);
    if not exists (select from club_private.members where id=member_id and club_id=c)
        and not exists (select from club_private.clubs where id=c and open_enrollment) then
        raise exception 'Enrollment is closed.' using errcode='42501';
    end if;
    select * into previous from club_private.members where id=member_id order by club_id limit 1;
    -- Roles belong to the club. Shared profile data follows the person.
    insert into club_private.members(club_id,id,name,kind,major,interests,experience,bio,"photoData",
                                      "graduationTerm","graduationYear","classStanding")
        values(c,member_id,trim(display_name),membership,coalesce(previous.major,''),
               coalesce(previous.interests,'{}'),coalesce(previous.experience,''),coalesce(previous.bio,''),
               previous."photoData",graduation_term,graduation_year,
               case when membership='student' then class_standing end)
        on conflict (club_id,id) do nothing;
    update club_private.members set name=trim(display_name), kind=membership,
        "graduationTerm"=graduation_term, "graduationYear"=graduation_year,
        "classStanding"=case when membership='student' then class_standing end
        where id=member_id;
end $$;

create function public.enroll_student(c text, display_name text, graduation_term text,
    graduation_year integer, class_standing text default null)
returns jsonb language plpgsql set search_path='' as $$
begin
    perform club_private.enroll_student(c,display_name,graduation_term,graduation_year,class_standing);
    return club_private.snapshot(c);
end $$;

create or replace function club_private.enroll(c text, display_name text)
returns void language plpgsql security definer set search_path='' as $$
begin
    perform club_private.require_usc();
    if not exists(select from club_private.members where club_id=c and id=auth.uid() and "graduationTerm" is not null) then
        raise exception 'Update Club Connect to enter your graduation details.' using errcode='22023';
    end if;
end $$;

create or replace function club_private.save_profile(c text, entry jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare
    member_id uuid := auth.uid();
    term text;
    yr integer;
    standing text;
    membership text;
begin
    perform club_private.require_member(c);
    perform pg_advisory_xact_lock(hashtextextended(member_id::text,0));
    if entry ? 'graduationTerm' or entry ? 'graduationYear' then
        term := entry->>'graduationTerm';
        yr := (entry->>'graduationYear')::integer;
        standing := entry->>'classStanding';
    else
        -- Older clients omit the academic fields. Keep the verified member's choices.
        select "graduationTerm","graduationYear","classStanding" into term,yr,standing
        from club_private.members where id=member_id and club_id=c;
    end if;
    membership := club_private.validate_graduation(term,yr,standing);
    update club_private.members set
        name=trim(entry->>'name'), kind=membership, major=entry->>'major',
        interests=array(select jsonb_array_elements_text(entry->'interests')),
        experience=entry->>'experience', bio=entry->>'bio', "photoData"=entry->>'photoData',
        "graduationTerm"=term, "graduationYear"=yr,
        "classStanding"=case when membership='student' then standing end
        where id=member_id;
end $$;

revoke all on function club_private.graduation_kind(text,integer,date),
    club_private.validate_graduation(text,integer,text),
    club_private.enroll_student(text,text,text,integer,text), public.enroll_student(text,text,text,integer,text)
    from public,anon,authenticated;
grant execute on function club_private.enroll_student(text,text,text,integer,text),
    public.enroll_student(text,text,text,integer,text) to authenticated;
