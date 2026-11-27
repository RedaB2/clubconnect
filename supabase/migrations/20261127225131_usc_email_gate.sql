-- Enforce the same mailbox policy at sign-up, email changes, and access time.
-- The exact domain excludes subdomains and lookalike suffixes.
create function club_private.is_usc_email(address text)
returns boolean language sql immutable strict set search_path='' as $$
    select lower(address) ~ '^[^@[:space:]]+@usc[.]edu$'
$$;

create function club_private.enforce_usc_identity() returns trigger
language plpgsql security definer set search_path='' as $$
begin
    if club_private.is_usc_email(new.email) is not true
       or (coalesce(new.email_change, '') <> '' and club_private.is_usc_email(new.email_change) is not true)
       or coalesce(new.is_anonymous, false)
       or coalesce(new.raw_app_meta_data->>'provider', 'email') <> 'email' then
        raise exception 'Use a USC email address to join Club Connect.' using errcode='23514';
    end if;
    return new;
end $$;
create trigger require_usc_identity before insert or update of email,email_change,raw_app_meta_data,is_anonymous
    on auth.users for each row execute function club_private.enforce_usc_identity();

-- The hook returns a readable error before Auth attempts mail delivery.
create function public.before_usc_signup(event jsonb) returns jsonb
language sql stable set search_path='' as $$
    select case when lower(coalesce(event->'user'->>'email','')) ~ '^[^@[:space:]]+@usc[.]edu$'
                      and coalesce(event->'user'->'app_metadata'->>'provider','email') = 'email'
        then '{}'::jsonb
        else jsonb_build_object('error', jsonb_build_object('http_code',403,'message','Use a USC email address to join Club Connect.'))
    end
$$;
revoke all on function public.before_usc_signup(jsonb) from public,anon,authenticated;
grant execute on function public.before_usc_signup(jsonb) to supabase_auth_admin;
revoke all on function club_private.enforce_usc_identity(), club_private.is_usc_email(text) from public,anon,authenticated;

create function club_private.require_usc() returns void
language plpgsql stable security definer set search_path='' as $$
begin
    if not exists (
        select from auth.users u
        where u.id = (select auth.uid()) and u.email_confirmed_at is not null
          and club_private.is_usc_email(u.email) and not coalesce(u.is_anonymous, false)
          and u.raw_app_meta_data->>'provider' = 'email'
    ) then
        raise exception 'Sign in with a verified USC email address.' using errcode='28000';
    end if;
end $$;
revoke all on function club_private.require_usc() from public,anon;
grant execute on function club_private.require_usc() to authenticated;

create or replace function club_private.require_member(c text, organizer boolean default false)
returns void language plpgsql stable security definer set search_path='' as $$
begin
    perform club_private.require_usc();
    if not exists (select from club_private.members where club_id=c and id=(select auth.uid()) and (not organizer or admin)) then
        raise exception 'Club membership or organizer access required.' using errcode='42501';
    end if;
end $$;

-- Compatibility with older app versions until the new academic enrollment RPC takes over.
create or replace function club_private.enroll(c text, display_name text)
returns void language plpgsql security definer set search_path='' as $$
begin
    perform club_private.require_usc();
    if not exists (select from club_private.clubs where id=c and open_enrollment) then raise exception 'Enrollment is closed.'; end if;
    insert into club_private.members(club_id,id,name) values(c,auth.uid(),trim(display_name)) on conflict do nothing;
end $$;

create or replace function club_private.delete_account() returns void language plpgsql security definer set search_path='' as $$
begin
    perform club_private.require_usc();
    delete from auth.users where id=auth.uid();
end $$;
