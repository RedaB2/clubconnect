-- psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f supabase/tests/usc_email.sql
begin;
set local plpgsql.check_asserts = on;
do $test$
declare
    student uuid := gen_random_uuid();
    invalid_id uuid := gen_random_uuid();
    result jsonb;
begin
    -- Every mailbox here is synthetic. Direct fixture creation sends no email.
    result := public.before_usc_signup(jsonb_build_object('user',jsonb_build_object('email',student||'@USC.edu')));
    assert result = '{}'::jsonb, 'Exact USC domain accepted regardless of case';
    result := public.before_usc_signup('{"user":{"email":"test@usc.edu.example"}}');
    assert result='{}'::jsonb and not club_private.is_usc_email('test@usc.edu.example'), 'Lookalikes have only the personal alumni path';
    result := public.before_usc_signup('{"user":{"email":"test@dept.usc.edu"}}');
    assert result='{}'::jsonb and not club_private.is_usc_email('test@dept.usc.edu'), 'Subdomains do not grant campus privileges';
    result := public.before_usc_signup('{"user":{"email":"test@usc.edu","app_metadata":{"provider":"apple"}}}');
    assert result->'error'->>'http_code' = '403', 'Other identity providers excluded';

    begin
        insert into auth.users (id,email,raw_app_meta_data) values(invalid_id,invalid_id||',x@example.invalid','{"provider":"email"}');
        raise exception 'Malformed personal account created' using errcode='XX000';
    exception when check_violation then null;
    end;
    insert into auth.users (id,email,raw_app_meta_data) values(student,student||'@usc.edu','{"provider":"email"}');
    begin
        update auth.users set email_change=student||'@example.invalid' where id=student;
        raise exception 'Non-USC pending change accepted' using errcode='XX000';
    exception when check_violation then null;
    end;
    begin
        update auth.users set email=student||'@example.invalid' where id=student;
        raise exception 'Non-USC identity assignment accepted' using errcode='XX000';
    exception when check_violation then null;
    end;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',student,'role','authenticated')::text,true);
    set local role authenticated;
    begin
        perform public.snapshot('menasa');
        raise exception 'Unverified user could access the app' using errcode='XX000';
    exception when invalid_authorization_specification then null;
    end;
    reset role;
    update auth.users set email_confirmed_at=now() where id=student;
    set local role authenticated;
    perform club_private.require_usc();
    begin
        perform public.snapshot('menasa');
        raise exception 'Verification implicitly enrolled the student' using errcode='XX000';
    exception when insufficient_privilege then null;
    end;
end
$test$;
rollback;
