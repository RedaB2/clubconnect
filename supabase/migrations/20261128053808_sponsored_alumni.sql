-- An invitation belongs to a club and mailbox. URLs identify a club and never grant access.
create table club_private.alumni_invitations (
    id uuid primary key default gen_random_uuid(),
    club_id text not null references club_private.clubs on delete cascade,
    email text not null check (email = lower(btrim(email)) and length(email) <= 254),
    sponsor uuid references auth.users on delete set null,
    created_at timestamptz not null default now(),
    expires_at timestamptz not null default (now() + interval '7 days'),
    revoked_at timestamptz,
    accepted_at timestamptz,
    accepted_by uuid references auth.users on delete cascade,
    check ((accepted_by is null) = (accepted_at is null)),
    check (accepted_at is null or revoked_at is null)
);
create unique index one_pending_alumni_invitation on club_private.alumni_invitations(email,club_id)
    where revoked_at is null and accepted_at is null;
create unique index one_accepted_alumni_membership on club_private.alumni_invitations(accepted_by,club_id)
    where accepted_by is not null;
create index alumni_invitation_club on club_private.alumni_invitations(club_id,created_at desc);
create index alumni_invitation_sponsor on club_private.alumni_invitations(sponsor) where sponsor is not null;
alter table club_private.alumni_invitations enable row level security;
revoke all on club_private.alumni_invitations from public,anon,authenticated;

create function club_private.signup_allowed(address text) returns boolean
language sql stable security definer set search_path='' as $$
    select coalesce(club_private.is_usc_email(address),false)
        or exists(select from club_private.alumni_invitations where email=lower(btrim(address))
                  and accepted_at is null and revoked_at is null and expires_at>statement_timestamp())
$$;
revoke all on function club_private.signup_allowed(text) from public,anon,authenticated;
grant usage on schema club_private to supabase_auth_admin;
grant execute on function club_private.signup_allowed(text) to supabase_auth_admin;

create or replace function public.before_usc_signup(event jsonb) returns jsonb
language sql stable set search_path='' as $$
    select case when coalesce(event->'user'->'app_metadata'->>'provider','email')='email'
              and not coalesce((event->'user'->>'is_anonymous')::boolean,false)
              and club_private.signup_allowed(event->'user'->>'email')
        then '{}'::jsonb else jsonb_build_object('error',jsonb_build_object('http_code',403,
            'message','Use your USC email or the personal address on your alumni invitation.')) end
$$;

create or replace function club_private.enforce_usc_identity() returns trigger
language plpgsql security definer set search_path='' as $$
begin
    if new.email is null or coalesce(new.is_anonymous,false) or coalesce(new.raw_app_meta_data->>'provider','email')<>'email' then
        raise exception 'An email account is required.' using errcode='23514';
    end if;
    if tg_op='INSERT' then
        if not club_private.signup_allowed(new.email) then
            raise exception 'A USC address or alumni invitation is required.' using errcode='23514';
        end if;
    elsif lower(old.email) is distinct from lower(new.email)
        and not (club_private.is_usc_email(old.email) and club_private.is_usc_email(new.email)) then
        raise exception 'This account is bound to its verified email address.' using errcode='23514';
    end if;
    if coalesce(new.email_change,'')<>'' and lower(new.email_change)<>lower(new.email)
        and not (club_private.is_usc_email(new.email) and club_private.is_usc_email(new.email_change)) then
        raise exception 'This account is bound to its verified email address.' using errcode='23514';
    end if;
    return new;
end $$;

create function club_private.verified_email() returns text
language plpgsql stable security definer set search_path='' as $$
declare address text;
begin
    select lower(btrim(u.email)) into address from auth.users u
    where u.id=(select auth.uid()) and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false)
          and u.raw_app_meta_data->>'provider'='email';
    if address is null then raise exception 'Sign in with a verified email address.' using errcode='28000'; end if;
    return address;
end $$;
revoke all on function club_private.verified_email() from public,anon,authenticated;

create or replace function club_private.require_usc() returns void
language plpgsql stable security definer set search_path='' as $$
begin
    if not club_private.is_usc_email(club_private.verified_email()) then
        raise exception 'This action requires a verified USC email.' using errcode='42501';
    end if;
end $$;

create or replace function club_private.require_member(c text, organizer boolean default false) returns void
language plpgsql stable security definer set search_path='' as $$
declare address text := club_private.verified_email();
begin
    if not exists(select from club_private.members m where m.club_id=c and m.id=(select auth.uid())
           and (not organizer or m.admin)
           and (club_private.is_usc_email(address) or (not organizer and exists (
               select from club_private.alumni_invitations i where i.club_id=c and i.accepted_by=m.id and i.email=address)))) then
        raise exception 'Club membership or organizer access required.' using errcode='42501';
    end if;
end $$;

-- A personal-address member cannot be promoted through organizer codes, handoffs,
-- or future membership creation paths. Profile edits recheck the academic category.
create function club_private.check_alumni_membership() returns trigger
language plpgsql security definer set search_path='' as $$
declare address text;
begin
    select lower(btrim(email)) into address from auth.users where id=new.id;
    if not club_private.is_usc_email(address) then
        if new.admin then raise exception 'Invited alumni participate as club members.' using errcode='42501'; end if;
        if not exists(select from club_private.alumni_invitations where accepted_by=new.id and club_id=new.club_id and email=address) then
            raise exception 'An accepted alumni invitation is required.' using errcode='42501';
        end if;
        if new.kind<>'alumni' or new."classStanding" is not null
           or club_private.graduation_kind(new."graduationTerm",new."graduationYear") is distinct from 'alumni' then
            raise exception 'Choose a completed graduation term for an alumni profile.' using errcode='22023';
        end if;
    end if;
    return new;
end $$;
revoke all on function club_private.check_alumni_membership() from public,anon,authenticated;
create trigger check_alumni_membership before insert or update of id,club_id,admin,kind,"graduationTerm","graduationYear","classStanding"
    on club_private.members for each row execute function club_private.check_alumni_membership();

create function club_private.invitation_json(i club_private.alumni_invitations) returns jsonb
language sql stable set search_path='' as $$
    select jsonb_build_object('id',i.id,'email',i.email,'expiresAt',extract(epoch from i.expires_at),
        'status',case when i.accepted_at is not null then 'accepted'
            when i.revoked_at < i.expires_at then 'revoked'
            when i.expires_at<=statement_timestamp() then 'expired' else 'pending' end)
$$;
create function club_private.alumni_invitations(c text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
    perform club_private.require_member(c,true);
    return (select coalesce(jsonb_agg(club_private.invitation_json(i) order by i.created_at desc,i.id),'[]'::jsonb)
            from club_private.alumni_invitations i where i.club_id=c);
end $$;
create function club_private.invite_alumnus(c text,address text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare mailbox text := lower(btrim(address)); invitation club_private.alumni_invitations;
begin
    perform club_private.require_member(c,true);
    if mailbox is null or length(mailbox)>254 or length(split_part(mailbox,'@',1))>64 or
       mailbox !~ '^[^@[:space:][:cntrl:]]+@[a-z0-9]([a-z0-9-]*[a-z0-9])?([.][a-z0-9]([a-z0-9-]*[a-z0-9])?)+$'
       or club_private.is_usc_email(mailbox) then
        raise exception 'Enter a personal email address for the alum.' using errcode='22023';
    end if;
    perform pg_advisory_xact_lock(hashtextextended(c||':'||mailbox,1));
    select * into invitation from club_private.alumni_invitations where club_id=c and email=mailbox
        and revoked_at is null order by (accepted_at is not null) desc,created_at desc limit 1 for update;
    if invitation.accepted_at is not null then
        raise exception 'This alum has already accepted a club invitation.' using errcode='22023';
    end if;
    if invitation.expires_at>clock_timestamp() then return club_private.invitation_json(invitation); end if;
    -- Close expired rows before issuing a fresh seven-day invitation.
    if invitation.id is not null then update club_private.alumni_invitations set revoked_at=clock_timestamp() where id=invitation.id; end if;
    insert into club_private.alumni_invitations(club_id,email,sponsor) values(c,mailbox,auth.uid()) returning * into invitation;
    return club_private.invitation_json(invitation);
end $$;
create function club_private.revoke_alumni_invitation(c text,invitation_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare invitation club_private.alumni_invitations;
begin
    perform club_private.require_member(c,true);
    select * into invitation from club_private.alumni_invitations where id=invitation_id and club_id=c for update;
    if not found then raise exception 'Invitation unavailable.' using errcode='42501'; end if;
    if invitation.accepted_at is not null then raise exception 'This invitation has already been accepted.' using errcode='22023'; end if;
    if invitation.revoked_at is null then update club_private.alumni_invitations set revoked_at=clock_timestamp() where id=invitation_id; end if;
end $$;

create function public.alumni_invitations(c text) returns jsonb language sql stable set search_path=''
as $$ select club_private.alumni_invitations(c) $$;
create function public.invite_alumnus(c text,address text) returns jsonb language sql set search_path=''
as $$ select club_private.invite_alumnus(c,address) $$;
create function public.revoke_alumni_invitation(c text,invitation_id uuid) returns void language sql set search_path=''
as $$ select club_private.revoke_alumni_invitation(c,invitation_id) $$;
revoke all on function club_private.invitation_json(club_private.alumni_invitations),
    club_private.alumni_invitations(text),club_private.invite_alumnus(text,text),club_private.revoke_alumni_invitation(text,uuid),
    public.alumni_invitations(text),public.invite_alumnus(text,text),public.revoke_alumni_invitation(text,uuid) from public,anon,authenticated;
grant execute on function club_private.alumni_invitations(text),club_private.invite_alumnus(text,text),club_private.revoke_alumni_invitation(text,uuid),
    public.alumni_invitations(text),public.invite_alumnus(text,text),public.revoke_alumni_invitation(text,uuid) to authenticated;

create or replace function club_private.club_catalog() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare address text := club_private.verified_email(); campus boolean := club_private.is_usc_email(address);
begin
    return (select coalesce(jsonb_agg(jsonb_build_object(
        'club',case when campus or m.id is not null then to_jsonb(b)-'open_enrollment'
                    else jsonb_build_object('id',b.id,'name',b.name,'fullName',b."fullName",'about','','accentHex',b."accentHex") end,
        'joined',m.id is not null,'isAdmin',coalesce(m.admin,false),
        'canJoin',case when campus then b.open_enrollment else true end) order by b.name,b.id),'[]'::jsonb)
        from club_private.clubs b left join club_private.members m on m.club_id=b.id and m.id=auth.uid()
        where (campus and (b.open_enrollment or m.id is not null)) or
              (not campus and exists (select from club_private.alumni_invitations i where i.club_id=b.id and i.email=address and
                  ((i.accepted_by=auth.uid() and m.id is not null) or
                   (i.accepted_at is null and i.revoked_at is null and i.expires_at>statement_timestamp())))));
end $$;

-- Only these two enrollment entry points consume invitations. The ordinary campus implementations
-- retain their original USC, open-enrollment and profile checks.
alter function club_private.enroll_student(text,text,text,integer,text) rename to enroll_usc_student;
alter function club_private.join_additional(text) rename to join_additional_usc;
revoke all on function club_private.enroll_usc_student(text,text,text,integer,text),club_private.join_additional_usc(text) from public,anon,authenticated;

create function club_private.accept_alumni(c text,display_name text,term text,yr integer) returns void
language plpgsql security definer set search_path='' as $$
declare address text := club_private.verified_email(); member_id uuid := auth.uid(); previous club_private.members%rowtype;
begin
    perform pg_advisory_xact_lock(hashtextextended(member_id::text,0));
    if exists(select from club_private.members where club_id=c and id=member_id) then
        perform club_private.require_member(c);
        return;
    end if;
    if club_private.validate_graduation(term,yr,null) <> 'alumni' then
        raise exception 'Choose a completed graduation term.' using errcode='22023';
    end if;
    -- Rechecks mailbox, club, expiry and consumption under the row lock.
    update club_private.alumni_invitations set accepted_by=member_id,accepted_at=clock_timestamp()
    where club_id=c and email=address and revoked_at is null and accepted_at is null and expires_at>clock_timestamp();
    if not found then raise exception 'A current alumni invitation for this club and email is required.' using errcode='42501'; end if;
    select * into previous from club_private.members where id=member_id order by club_id limit 1;
    insert into club_private.members(club_id,id,name,kind,"graduationTerm","graduationYear",major,interests,experience,bio,"photoData")
        values(c,member_id,coalesce(previous.name,trim(display_name)),'alumni',coalesce(previous."graduationTerm",term),
               coalesce(previous."graduationYear",yr),coalesce(previous.major,''),coalesce(previous.interests,'{}'),
               coalesce(previous.experience,''),coalesce(previous.bio,''),previous."photoData");
end $$;
revoke all on function club_private.accept_alumni(text,text,text,integer) from public,anon,authenticated;

create function club_private.enroll_student(c text,display_name text,graduation_term text,graduation_year integer,class_standing text)
returns void language plpgsql security definer set search_path='' as $$
begin
    if club_private.is_usc_email(club_private.verified_email()) then
        perform club_private.enroll_usc_student(c,display_name,graduation_term,graduation_year,class_standing);
    else
        if class_standing is not null then raise exception 'Invited alumni need a completed graduation term.' using errcode='22023'; end if;
        perform club_private.accept_alumni(c,display_name,graduation_term,graduation_year);
    end if;
end $$;
create function club_private.join_additional(c text) returns void
language plpgsql security definer set search_path='' as $$
declare previous club_private.members%rowtype;
begin
    if club_private.is_usc_email(club_private.verified_email()) then
        perform club_private.join_additional_usc(c);
    else
        select * into previous from club_private.members where id=auth.uid() order by club_id limit 1;
        if not found then raise exception 'Complete your invited alumni profile first.' using errcode='42501'; end if;
        perform club_private.accept_alumni(c,previous.name,previous."graduationTerm",previous."graduationYear");
    end if;
end $$;
revoke all on function club_private.enroll_student(text,text,text,integer,text),club_private.join_additional(text) from public,anon,authenticated;
grant execute on function club_private.enroll_student(text,text,text,integer,text),club_private.join_additional(text) to authenticated;

create or replace function club_private.can_listen_to_mailbox(channel text) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare address text := club_private.verified_email();
begin
    return exists(select from club_private.members m where m.id=(select auth.uid()) and channel='mail:'||m.id||':'||m.club_id
        and (club_private.is_usc_email(address) or exists(select from club_private.alumni_invitations i where
            i.club_id=m.club_id and i.accepted_by=m.id and i.email=address)));
end $$;

create or replace function club_private.delete_account() returns void language plpgsql security definer set search_path='' as $$
declare address text := club_private.verified_email();
begin
    delete from club_private.alumni_invitations where email=address;
    delete from auth.users where id=auth.uid();
end $$;
