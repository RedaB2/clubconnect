-- Run against a migrated Supabase database as postgres:
-- psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/pilot_flows.sql
begin;
set local plpgsql.check_asserts = on;

do $pilot_test$
declare
    organizer uuid := gen_random_uuid();
    student uuid := gen_random_uuid();
    club text := 'regression-' || gen_random_uuid();
    invitation text := gen_random_uuid()::text;
    first_event uuid := gen_random_uuid();
    second_event uuid := gen_random_uuid();
    event_data jsonb;
    profile_data jsonb := '{
        "name":"Pilot student", "kind":"alumni", "major":"Architecture",
        "graduationTerm":"fall", "graduationYear":2020,
        "interests":["Film","Design"], "experience":"Event planning", "bio":"Pilot fixture", "photoData":"AQID"
    }';
    club_data jsonb := '{
        "name":"Pilot","fullName":"Pilot fixture association","about":"Regression club",
        "accentHex":"#975030","secondaryHex":"#254E77","logoData":"AwIB"
    }';
    state jsonb;
    ticket jsonb;
    ticket_code text;
    organizer_ticket jsonb;
begin
    -- Creation of disposable test identities and a private club is the only
    -- privileged setup. All subsequent actions use the authenticated RPC role.
    insert into auth.users (id, email, email_confirmed_at, raw_app_meta_data) values
        (organizer, organizer || '@usc.edu', now(), '{"provider":"email"}'),
        (student, student || '@usc.edu', now(), '{"provider":"email"}');
    insert into club_private.clubs (id, name, "fullName", about, "accentHex")
        values (club, 'Pilot', 'Pilot fixture', '', '#554433');
    insert into club_private.organizer_invites (club_id, digest)
        values (club, sha256(convert_to(invitation, 'UTF8')));

    assert club_private.graduation_kind('spring', 2027, date '2027-05-31') = 'student';
    assert club_private.graduation_kind('spring', 2027, date '2027-06-01') = 'alumni';
    assert club_private.graduation_kind('fall', 2027, date '2027-12-31') = 'student';
    assert club_private.graduation_kind('fall', 2027, date '2028-01-01') = 'alumni';

    set local role authenticated;
    perform set_config('request.jwt.claims', jsonb_build_object('sub', organizer, 'role', 'authenticated')::text, true);
    state := public.enroll_student(club, 'Pilot organizer', 'spring', extract(year from now())::int + 1, 'senior');
    assert state->>'myID' = organizer::text and state->'isAdmin' = 'false'::jsonb, 'Enrollment starts as an ordinary member';
    state := public.claim_organizer(invitation, club);
    assert state->'isAdmin' = 'true'::jsonb, 'Organizer invitation grants organizer access';

    event_data := jsonb_build_object('id', first_event, 'title', 'First pilot event', 'location', 'Campus',
        'summary', 'Fixture', 'startsAt', now() + interval '1 day', 'endsAt', now() + interval '2 days', 'category', 'Social');
    perform public.save_event(event_data, club);
    perform public.save_event(event_data || jsonb_build_object('id', second_event, 'title', 'Second pilot event'), club);
    state := public.save_club(club_data, club);
    assert (state->'club') @> club_data, 'Organizer can save club details, color, and logo';
    state := public.save_club(club_data - 'secondaryHex', club);
    assert state->'club'->>'secondaryHex' = '#254E77', 'Older client saves preserve the secondary color';
    state := public.set_rsvp(first_event, true, club);
    organizer_ticket := state->'tickets'->0;

    perform set_config('request.jwt.claims', jsonb_build_object('sub', student, 'role', 'authenticated')::text, true);
    begin
        perform public.enroll_student(club, 'Fixture student', 'spring', extract(year from now())::int + 1, null);
        raise exception 'A current student enrolled without choosing a standing' using errcode='XX000';
    exception when invalid_parameter_value then null;
    end;
    state := public.enroll_student(club, 'Fixture student', 'spring', extract(year from now())::int + 1, 'junior');
    assert state->'tickets' = '[]'::jsonb, 'A new member has no tickets from other members';
    assert (state->'club') @> club_data, 'Club settings and logo persist for another member';
    begin
        perform public.claim_organizer(invitation, club);
        raise exception 'A used organizer invitation was accepted' using errcode = 'XX000';
    exception when raise_exception then
        assert sqlerrm = 'This organizer invitation is invalid or already used.';
    end;
    begin
        perform public.save_event(event_data, club);
        raise exception 'Ordinary member edited an event' using errcode = 'XX000';
    exception when insufficient_privilege then null;
    end;
    begin
        perform public.save_club(club_data, club);
        raise exception 'Ordinary member edited club settings' using errcode = 'XX000';
    exception when insufficient_privilege then null;
    end;

    perform public.save_profile(profile_data, club);
    state := public.set_rsvp(first_event, true, club);
    ticket := state->'tickets'->0;
    ticket_code := ticket->>'code';
    assert ticket_code is not null and ticket_code <> organizer_ticket->>'code', 'Each attendee has a distinct ticket';
    state := public.set_rsvp(first_event, true, club);
    assert state->'tickets' = jsonb_build_array(ticket), 'A repeated RSVP returns the same single private ticket';
    begin
        perform public.check_in(first_event, ticket_code, club);
        raise exception 'Ordinary member checked in a ticket' using errcode = 'XX000';
    exception when insufficient_privilege then null;
    end;

    perform set_config('request.jwt.claims', jsonb_build_object('sub', organizer, 'role', 'authenticated')::text, true);
    state := public.snapshot(club);
    assert state->'tickets' = jsonb_build_array(organizer_ticket), 'Organizer snapshot contains only their own tickets';
    assert (state->'members') @> jsonb_build_array(profile_data || jsonb_build_object('id', student)), 'Edited profile is visible across accounts';
    begin
        perform public.check_in(second_event, ticket_code, club);
        raise exception 'Wrong event accepted a ticket' using errcode = 'XX000';
    exception when raise_exception then
        assert sqlerrm = 'No matching ticket for this event.';
    end;
    assert public.check_in(first_event, ticket_code, club) = 'Pilot student', 'Organizer checks in the correct attendee';
    begin
        perform public.check_in(first_event, ticket_code, club);
        raise exception 'Repeated check-in succeeded' using errcode = 'XX000';
    exception when raise_exception then
        assert sqlerrm = 'This ticket has already been checked in.';
    end;

    perform set_config('request.jwt.claims', jsonb_build_object('sub', student, 'role', 'authenticated')::text, true);
    state := public.snapshot(club);
    assert state->'tickets'->0->'checkedIn' = 'true'::jsonb, 'Check-in persists for the attendee';
    perform public.delete_account();
    begin
        perform public.snapshot(club);
        raise exception 'Deleted member retained access' using errcode = 'XX000';
    exception when invalid_authorization_specification then null;
    end;

    perform set_config('request.jwt.claims', jsonb_build_object('sub', organizer, 'role', 'authenticated')::text, true);
    state := public.snapshot(club);
    assert jsonb_array_length(state->'members') = 1 and state->'members'->0->>'id' = organizer::text,
        'Deleting an account removes only its member profile';
    assert state->'tickets' = jsonb_build_array(organizer_ticket), 'Deleting another member preserves the organizer ticket';
    begin
        perform public.check_in(first_event, ticket_code, club);
        raise exception 'Deleted member retained a ticket' using errcode = 'XX000';
    exception when raise_exception then
        assert sqlerrm = 'No matching ticket for this event.';
    end;
end
$pilot_test$;

rollback;
