-- Retain a minimal identity for the applicant’s own requests if a club closes admission.
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
        where b.open_enrollment or m.id is not null or (
            not campus and exists(select from club_private.alumni_applications a where a.club_id=b.id and a.applicant=auth.uid())));
end $$;
