create or replace function club_private.snapshot(c text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare result jsonb;
begin
    perform club_private.require_member(c);
    select jsonb_build_object(
        'club', (select to_jsonb(b)-'open_enrollment' from club_private.clubs b where id=c),
        'members', coalesce((select jsonb_agg((to_jsonb(m)-'club_id'-'admin') ||
            jsonb_build_object('kind',coalesce(club_private.graduation_kind(m."graduationTerm",m."graduationYear"),m.kind))
            order by m.name,m.id) from club_private.members m where club_id=c), '[]'),
        'events', coalesce((select jsonb_agg(to_jsonb(e)-'club_id' order by e."startsAt") from club_private.events e where club_id=c), '[]'),
        'tickets', coalesce((select jsonb_agg(to_jsonb(t)-'club_id'-'owner') from club_private.tickets t where club_id=c and owner=(select auth.uid())), '[]'),
        'myID', auth.uid(), 'isAdmin', (select admin from club_private.members where club_id=c and id=(select auth.uid()))
    ) into result;
    return result;
end $$;
