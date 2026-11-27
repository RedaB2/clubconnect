-- A confirmed returning member with legacy rows in two clubs completes one campus profile.
begin;
set local plpgsql.check_asserts = on;

do $$
declare
    person uuid := gen_random_uuid();
    first_club text := 'academic-' || gen_random_uuid();
    second_club text := 'academic-' || gen_random_uuid();
    next_year integer := extract(year from now() at time zone 'America/Los_Angeles')::integer + 1;
    snapshot jsonb;
    edited jsonb;
begin
    insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data)
        values(person,person || '@usc.edu',now(),'{"provider":"email"}');
    insert into club_private.clubs(id,name,"fullName",about,"accentHex")
        values(first_club,'First','First club','','#974A30'),(second_club,'Second','Second club','','#974A30');
    insert into club_private.members(club_id,id,name,admin,major)
        values(first_club,person,'Returning member',true,'Design'),(second_club,person,'Returning member',false,'Design');

    set local role authenticated;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',person,'role','authenticated')::text,true);
    snapshot := public.snapshot(first_club);
    assert snapshot->'members'->0->>'graduationYear' is null, 'Legacy graduation year stays unknown';
    begin
        perform public.join_club('Returning member',first_club);
        raise exception 'Legacy enrollment bypassed graduation requirements' using errcode='XX000';
    exception when invalid_parameter_value then null;
    end;
    snapshot := public.enroll_student(first_club,'Returning student','spring',next_year,'junior');
    assert snapshot->>'isAdmin' = 'true' and snapshot->'members'->0->>'major' = 'Design';
    snapshot := public.snapshot(second_club);
    assert snapshot->>'isAdmin' = 'false' and snapshot->'members'->0->>'classStanding' = 'junior';
    edited := (snapshot->'members'->0) || '{"name":"Graduate","graduationYear":2005,"graduationTerm":"fall","kind":"student"}';
    perform public.save_profile(edited,second_club);
    snapshot := public.snapshot(first_club);
    assert snapshot->'members'->0->>'kind' = 'alumni' and snapshot->'members'->0->>'name' = 'Graduate';
    assert snapshot->'members'->0->>'classStanding' is null and snapshot->>'isAdmin' = 'true';
    -- A previous app build saves a bio without erasing the new academic fields.
    edited := ((snapshot->'members'->0) - 'graduationTerm' - 'graduationYear' - 'classStanding')
        || '{"bio":"Updated bio","kind":"student"}';
    snapshot := public.save_profile(edited,first_club);
    assert snapshot->'members'->0->>'graduationTerm' = 'fall' and snapshot->'members'->0->>'kind' = 'alumni';
    assert (public.snapshot(second_club))->'members'->0->>'bio' = 'Updated bio';
end $$;
rollback;
