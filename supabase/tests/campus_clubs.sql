begin;
set local plpgsql.check_asserts = on;
do $test$
declare
    a uuid := gen_random_uuid();
    b uuid := gen_random_uuid();
    campus uuid := gen_random_uuid();
    second uuid := gen_random_uuid();
    user_id uuid;
    s jsonb;
    p jsonb;
    failed boolean := false;
begin
    foreach user_id in array array[a,b] loop
        insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data)
            values(user_id,user_id::text||'@usc.edu',now(),'{"provider":"email"}');
    end loop;
    set local role authenticated;
    perform set_config('request.jwt.claims', jsonb_build_object('sub',a,'role','authenticated')::text, true);
    p := jsonb_build_object('name','Campus Member','graduationTerm','fall','graduationYear',extract(year from now())::integer + 2,'classStanding','junior');
    s := public.create_campus_club(campus,'Club A',p);
    assert s->'club'->>'accentHex'='#80523F' and s->'club'->>'secondaryHex'='#F0E4D9',
        'New clubs start with the Club Connect palette';
    assert (s->>'isAdmin')::boolean and s->'members'->0->>'name'='Campus Member';
    assert jsonb_array_length(s->'members')=1;
    s := public.create_campus_club(campus,'Club A',p);
    assert jsonb_array_length(s->'members')=1, 'Retry creation must not duplicate membership';
    s := public.create_campus_club(second,'Club B');
    assert s->'members'->0->>'graduationTerm'='fall';
    assert (select count(*) from jsonb_array_elements(public.club_catalog()) e where (e->>'isAdmin')::boolean)=2;
    begin perform public.step_down(campus::text); exception when raise_exception then failed := true; end;
    assert failed, 'A sole organizer must name a replacement';
    perform set_config('request.jwt.claims', jsonb_build_object('sub',b,'role','authenticated')::text, true);
    s := public.enroll_student(campus::text,'Other Member','spring',2020,null);
    assert not (s->>'isAdmin')::boolean;
    s := public.join_additional(second::text);
    assert not (s->>'isAdmin')::boolean and jsonb_array_length(s->'members')=2;
    s := public.join_additional(second::text);
    assert jsonb_array_length(s->'members')=2;
    failed := false;
    begin perform public.create_campus_club(campus,'Retry as a different user',p); exception when insufficient_privilege then failed := true; end;
    assert failed, 'A retry must never grant a role to a second account';
    perform set_config('request.jwt.claims', jsonb_build_object('sub',a,'role','authenticated')::text, true);
    s := public.step_down(campus::text,b);
    assert not (s->>'isAdmin')::boolean;
    assert (public.snapshot(second::text)->>'isAdmin')::boolean, 'Other organizer role must survive';
    perform set_config('request.jwt.claims', jsonb_build_object('sub',b,'role','authenticated')::text, true);
    assert (public.snapshot(campus::text)->>'isAdmin')::boolean, 'The successor can manage the club';
    assert not (public.snapshot(second::text)->>'isAdmin')::boolean;
    reset role;
end $test$;
rollback;
