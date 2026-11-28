-- A verified personal mailbox can hold an alumni profile without any club membership.
create table club_private.alumni_profiles (
    id uuid primary key references auth.users on delete cascade,
    name text not null check(length(trim(name)) between 1 and 100),
    "graduationTerm" text not null check("graduationTerm" in ('spring','fall')),
    "graduationYear" integer not null check("graduationYear" between 1900 and 2200),
    major text not null default '' check(length(major)<=200),
    interests text[] not null default '{}' check(cardinality(interests)<=40 and length(interests::text)<=3000),
    experience text not null default '' check(length(experience)<=4000),
    bio text not null default '' check(length(bio)<=4000),
    "photoData" text check(length("photoData")<=160000)
);
create table club_private.alumni_applications (
    id uuid primary key default gen_random_uuid(),
    club_id text not null references club_private.clubs on delete cascade,
    applicant uuid not null references club_private.alumni_profiles on delete cascade,
    note text not null default '' check(length(note)<=300),
    status text not null default 'pending' check(status in ('pending','approved','declined','withdrawn')),
    submitted_at timestamptz not null default clock_timestamp(),
    decided_at timestamptz,
    decided_by uuid references auth.users on delete set null,
    check((status='pending')=(decided_at is null))
);
create unique index active_alumni_application on club_private.alumni_applications(applicant,club_id) where status in ('pending','approved');
create index my_alumni_applications on club_private.alumni_applications(applicant,club_id,submitted_at desc,id desc);
create index club_alumni_queue on club_private.alumni_applications(club_id,status,submitted_at desc);
create index alumni_application_reviewer on club_private.alumni_applications(decided_by) where decided_by is not null;
alter table club_private.alumni_profiles enable row level security;
alter table club_private.alumni_applications enable row level security;
revoke all on club_private.alumni_profiles,club_private.alumni_applications from public,anon,authenticated;

-- Preserve previously accepted memberships. Unused legacy invitations no longer authorize enrollment.
insert into club_private.alumni_profiles(id,name,"graduationTerm","graduationYear",major,interests,experience,bio,"photoData")
select distinct on(m.id) m.id,m.name,m."graduationTerm",m."graduationYear",m.major,m.interests,m.experience,m.bio,m."photoData"
from club_private.members m join club_private.alumni_invitations i on i.club_id=m.club_id and i.accepted_by=m.id
order by m.id,m.club_id;
insert into club_private.alumni_applications(club_id,applicant,status,submitted_at,decided_at,decided_by)
select i.club_id,i.accepted_by,'approved',i.created_at,i.accepted_at,i.sponsor from club_private.alumni_invitations i
join club_private.members m on m.id=i.accepted_by and m.club_id=i.club_id;
update club_private.alumni_invitations set revoked_at=clock_timestamp() where revoked_at is null and accepted_at is null;
revoke execute on function public.alumni_invitations(text),public.invite_alumnus(text,text),public.revoke_alumni_invitation(text,uuid),
    club_private.alumni_invitations(text),club_private.invite_alumnus(text,text),club_private.revoke_alumni_invitation(text,uuid) from authenticated;

create or replace function club_private.signup_allowed(address text) returns boolean
language sql stable security definer set search_path='' as $$
    select coalesce(club_private.is_usc_email(address),false) or club_private.personal_mailbox(address) is not null
$$;
create or replace function public.before_usc_signup(event jsonb) returns jsonb
language sql stable set search_path='' as $$
    select case when coalesce(event->'user'->'app_metadata'->>'provider','email')='email'
            and not coalesce((event->'user'->>'is_anonymous')::boolean,false) and club_private.signup_allowed(event->'user'->>'email')
        then '{}'::jsonb else jsonb_build_object('error',jsonb_build_object('http_code',403,'message','Enter a valid email address to join Club Connect.')) end
$$;

create function club_private.require_alumni_account() returns void
language plpgsql stable security definer set search_path='' as $$
begin
    if club_private.personal_mailbox(club_private.verified_email()) is null then
        raise exception 'A verified personal email address is required.' using errcode='42501';
    end if;
end $$;

create function club_private.approved_alum(c text,person uuid) returns boolean
language sql stable security definer set search_path='' as $$
    select exists(select from club_private.alumni_applications a where a.applicant=person and a.club_id=c and a.status='approved')
$$;
create or replace function club_private.require_member(c text,organizer boolean default false) returns void
language plpgsql stable security definer set search_path='' as $$
declare campus boolean := club_private.is_usc_email(club_private.verified_email());
begin
    if not exists(select from club_private.members m where m.club_id=c and m.id=(select auth.uid()) and (not organizer or m.admin)
           and (campus or (not organizer and club_private.approved_alum(c,m.id)))) then
        raise exception 'Club membership or organizer access required.' using errcode='42501';
    end if;
end $$;
create or replace function club_private.check_alumni_membership() returns trigger
language plpgsql security definer set search_path='' as $$
begin
    if not exists(select from auth.users u where u.id=new.id and club_private.is_usc_email(u.email)) then
        if new.admin then raise exception 'Personal-email alumni participate as club members.' using errcode='42501'; end if;
        if not club_private.approved_alum(new.club_id,new.id) then raise exception 'Organizer approval is required.' using errcode='42501'; end if;
        if new.kind<>'alumni' or new."classStanding" is not null
           or club_private.graduation_kind(new."graduationTerm",new."graduationYear") is distinct from 'alumni' then
            raise exception 'Choose a completed graduation term.' using errcode='22023';
        end if;
    end if;
    return new;
end $$;
create or replace function club_private.can_listen_to_mailbox(channel text) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare campus boolean:=club_private.is_usc_email(club_private.verified_email());
begin
    return exists(select from club_private.members m where m.id=(select auth.uid()) and channel='mail:'||m.id||':'||m.club_id
        and (campus or club_private.approved_alum(m.club_id,m.id)));
end $$;
create or replace function club_private.enroll_student(c text,display_name text,graduation_term text,graduation_year integer,class_standing text)
returns void language sql security definer set search_path='' as $$
    select club_private.enroll_usc_student(c,display_name,graduation_term,graduation_year,class_standing)
$$;
create or replace function club_private.join_additional(c text) returns void language sql security definer set search_path='' as $$
    select club_private.join_additional_usc(c)
$$;
drop function club_private.accept_alumni(text,text,text,integer);

create or replace function club_private.club_catalog() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare address text:=club_private.verified_email(); campus boolean:=club_private.is_usc_email(address);
begin
    if not campus and not exists(select from club_private.alumni_profiles where id=auth.uid()) then return '[]'::jsonb; end if;
    return (select coalesce(jsonb_agg(jsonb_build_object(
        'club',case when campus or m.id is not null then to_jsonb(b)-'open_enrollment'
               else jsonb_build_object('id',b.id,'name',b.name,'fullName',b."fullName",'about',left(b.about,300),'accentHex',b."accentHex",'secondaryHex',b."secondaryHex") end,
        'joined',m.id is not null,'isAdmin',coalesce(m.admin,false),'canJoin',b.open_enrollment) ||
        case when m.admin then jsonb_build_object('pendingRequestCount',(select count(*) from club_private.alumni_applications a
            where a.club_id=b.id and a.status='pending')) else '{}'::jsonb end
        order by b.name,b.id),'[]'::jsonb)
        from club_private.clubs b left join club_private.members m on m.club_id=b.id and m.id=auth.uid() and
            (campus or club_private.approved_alum(b.id,m.id))
        where b.open_enrollment or m.id is not null);
end $$;

create function club_private.save_alumni_profile(entry jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare person uuid:=auth.uid(); p club_private.alumni_profiles%rowtype;
begin
    perform club_private.require_alumni_account();
    perform pg_advisory_xact_lock(hashtextextended(person::text,0));
    select * into p from club_private.alumni_profiles where id=person;
    -- Never take the UUID, account email, campus affiliation or organizer flag from the client.
    p:=jsonb_populate_record(p,entry-'id');
    if p."graduationTerm" is null or p."graduationYear" is null or
       club_private.validate_graduation(p."graduationTerm",p."graduationYear",null)<>'alumni' then
        raise exception 'Choose a completed graduation term.' using errcode='22023';
    end if;
    if p.name is null or length(trim(p.name)) not between 1 and 100 then raise exception 'Enter your full name.' using errcode='22023'; end if;
    insert into club_private.alumni_profiles(id,name,"graduationTerm","graduationYear",major,interests,experience,bio,"photoData")
       values(person,trim(p.name),p."graduationTerm",p."graduationYear",coalesce(p.major,''),coalesce(p.interests,'{}'),coalesce(p.experience,''),coalesce(p.bio,''),p."photoData")
       on conflict(id) do update set name=excluded.name,"graduationTerm"=excluded."graduationTerm","graduationYear"=excluded."graduationYear",
           major=excluded.major,interests=excluded.interests,experience=excluded.experience,bio=excluded.bio,"photoData"=excluded."photoData";
    update club_private.members m set name=p.name,"graduationTerm"=p."graduationTerm","graduationYear"=p."graduationYear",
        major=coalesce(p.major,''),interests=coalesce(p.interests,'{}'),experience=coalesce(p.experience,''),bio=coalesce(p.bio,''),"photoData"=p."photoData"
        where m.id=person;
end $$;
alter function club_private.save_profile(text,jsonb) rename to save_campus_profile;
revoke execute on function club_private.save_campus_profile(text,jsonb) from authenticated;
create function club_private.save_profile(c text,entry jsonb) returns void
language plpgsql security definer set search_path='' as $$
begin
    perform club_private.require_member(c);
    if club_private.is_usc_email(club_private.verified_email()) then perform club_private.save_campus_profile(c,entry);
    else perform club_private.save_alumni_profile(entry); end if;
end $$;
revoke all on function club_private.save_profile(text,jsonb) from public,anon;
grant execute on function club_private.save_profile(text,jsonb) to authenticated;

create function club_private.application_json(a club_private.alumni_applications,p club_private.alumni_profiles,address text) returns jsonb
language sql stable set search_path='' as $$
    select jsonb_build_object('id',a.id,'clubID',a.club_id,'name',p.name,'email',address,'graduationTerm',p."graduationTerm",'graduationYear',p."graduationYear",
        'note',a.note,'status',a.status,'submittedAt',extract(epoch from a.submitted_at),'decidedAt',extract(epoch from a.decided_at))
$$;
create function club_private.alumni_workspace() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare address text:=club_private.verified_email(); person uuid:=auth.uid(); p club_private.alumni_profiles%rowtype;
begin
    perform club_private.require_alumni_account();
    select * into p from club_private.alumni_profiles where id=person;
    return jsonb_build_object('profile',case when p.id is not null then to_jsonb(p)||jsonb_build_object('kind','alumni') end,
        'applications',(select coalesce(jsonb_agg(club_private.application_json(a,p,address) order by a.submitted_at desc),'[]'::jsonb)
            from (select distinct on(club_id) * from club_private.alumni_applications where applicant=person order by club_id,submitted_at desc,id desc) a),
        'catalog',club_private.club_catalog());
end $$;
create function club_private.request_alumni_membership(c text,note text) returns void
language plpgsql security definer set search_path='' as $$
declare person uuid:=auth.uid(); latest club_private.alumni_applications%rowtype;
begin
    perform club_private.require_alumni_account();
    perform pg_advisory_xact_lock(hashtextextended(person::text,0));
    if not exists(select from club_private.alumni_profiles where id=person) then raise exception 'Create your alumni profile first.' using errcode='42501'; end if;
    select * into latest from club_private.alumni_applications where applicant=person and club_id=c order by submitted_at desc,id desc limit 1 for update;
    if latest.status in ('pending','approved') then return; end if;
    if not exists(select from club_private.clubs where id=c and open_enrollment) then raise exception 'This club is unavailable for requests.' using errcode='42501'; end if;
    if length(trim(coalesce(note,'')))>300 then raise exception 'Keep your club note to 300 characters.' using errcode='22023'; end if;
    insert into club_private.alumni_applications(club_id,applicant,note) values(c,person,trim(coalesce(note,'')));
end $$;
create function club_private.withdraw_alumni_request(c text) returns void
language plpgsql security definer set search_path='' as $$
declare latest club_private.alumni_applications%rowtype;
begin
    perform club_private.require_alumni_account();
    perform pg_advisory_xact_lock(hashtextextended(auth.uid()::text,0));
    select * into latest from club_private.alumni_applications where applicant=auth.uid() and club_id=c order by submitted_at desc,id desc limit 1 for update;
    if latest.status='withdrawn' then return; end if;
    if latest.status is distinct from 'pending' then raise exception 'Only pending requests can be withdrawn.' using errcode='22023'; end if;
    update club_private.alumni_applications set status='withdrawn',decided_at=clock_timestamp() where id=latest.id;
end $$;
create function club_private.review_alumni_applications(c text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
    perform club_private.require_member(c,true);
    return (select coalesce(jsonb_agg(club_private.application_json(a,p,lower(u.email)) order by
            (a.status='pending') desc,a.submitted_at desc,a.id),'[]'::jsonb)
        from club_private.alumni_applications a join club_private.alumni_profiles p on p.id=a.applicant
        join auth.users u on u.id=a.applicant where a.club_id=c);
end $$;
create function club_private.decide_alumni_application(c text,application_id uuid,approve boolean) returns void
language plpgsql security definer set search_path='' as $$
declare a club_private.alumni_applications%rowtype; p club_private.alumni_profiles%rowtype; decision text;
begin
    perform club_private.require_member(c,true);
    if approve is null then raise exception 'Choose a decision.' using errcode='22023'; end if;
    decision:=case when approve then 'approved' else 'declined' end;
    select * into a from club_private.alumni_applications where id=application_id and club_id=c;
    if not found then raise exception 'Request unavailable.' using errcode='42501'; end if;
    -- Serialize approval with the applicant’s profile edits, withdrawal and resubmission.
    perform pg_advisory_xact_lock(hashtextextended(a.applicant::text,0));
    select * into a from club_private.alumni_applications where id=application_id and club_id=c for update;
    if not found then raise exception 'Request unavailable.' using errcode='42501'; end if;
    if a.status=decision then return; end if;
    if a.status<>'pending' then raise exception 'This request is no longer pending.' using errcode='22023'; end if;
    if not exists(select from auth.users u where u.id=a.applicant and u.email_confirmed_at is not null and u.raw_app_meta_data->>'provider'='email'
           and not coalesce(u.is_anonymous,false) and club_private.personal_mailbox(u.email) is not null) then
        raise exception 'The verified applicant account is unavailable.' using errcode='42501';
    end if;
    update club_private.alumni_applications set status=decision,decided_at=clock_timestamp(),decided_by=auth.uid() where id=a.id;
    if approve then
        select * into strict p from club_private.alumni_profiles where id=a.applicant;
        insert into club_private.members(club_id,id,name,kind,major,interests,experience,bio,"photoData","graduationTerm","graduationYear")
        values(c,p.id,p.name,'alumni',p.major,p.interests,p.experience,p.bio,p."photoData",p."graduationTerm",p."graduationYear");
    end if;
end $$;

create function public.alumni_workspace() returns jsonb language sql stable set search_path='' as $$ select club_private.alumni_workspace() $$;
create function public.save_alumni_profile(entry jsonb) returns void language sql set search_path='' as $$ select club_private.save_alumni_profile(entry) $$;
create function public.request_alumni_membership(c text,note text default '') returns void language sql set search_path='' as $$ select club_private.request_alumni_membership(c,note) $$;
create function public.withdraw_alumni_request(c text) returns void language sql set search_path='' as $$ select club_private.withdraw_alumni_request(c) $$;
create function public.review_alumni_applications(c text) returns jsonb language sql stable set search_path='' as $$ select club_private.review_alumni_applications(c) $$;
create function public.decide_alumni_application(c text,application_id uuid,approve boolean) returns void language sql set search_path='' as $$
    select club_private.decide_alumni_application(c,application_id,approve) $$;
revoke all on function club_private.require_alumni_account(),club_private.approved_alum(text,uuid),
    club_private.application_json(club_private.alumni_applications,club_private.alumni_profiles,text) from public,anon,authenticated;
do $$
declare fn regprocedure;
begin
    foreach fn in array array[
        'public.alumni_workspace()'::regprocedure,'club_private.alumni_workspace()'::regprocedure,
        'public.save_alumni_profile(jsonb)'::regprocedure,'club_private.save_alumni_profile(jsonb)'::regprocedure,
        'public.request_alumni_membership(text,text)'::regprocedure,'club_private.request_alumni_membership(text,text)'::regprocedure,
        'public.withdraw_alumni_request(text)'::regprocedure,'club_private.withdraw_alumni_request(text)'::regprocedure,
        'public.review_alumni_applications(text)'::regprocedure,'club_private.review_alumni_applications(text)'::regprocedure,
        'public.decide_alumni_application(text,uuid,boolean)'::regprocedure,'club_private.decide_alumni_application(text,uuid,boolean)'::regprocedure
    ] loop
        execute format('revoke all on function %s from public,anon,authenticated',fn);
        execute format('grant execute on function %s to authenticated',fn);
    end loop;
end $$;
