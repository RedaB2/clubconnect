create function club_private.delete_account() returns void language plpgsql security definer set search_path='' as $$
begin
    if auth.uid() is null then raise exception 'Sign in to delete your account.' using errcode='42501'; end if;
    delete from auth.users where id=auth.uid();
end $$;
create function public.delete_account() returns void language sql set search_path='' as $$ select club_private.delete_account() $$;
revoke all on function club_private.delete_account(), public.delete_account() from public, anon;
grant execute on function club_private.delete_account(), public.delete_account() to authenticated;
