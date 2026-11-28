-- One address per invitation, also safe for a preaddressed Mail draft.
create function club_private.personal_mailbox(address text) returns text
language sql immutable strict set search_path='' as $$
    select case when length(box)<=254 and length(split_part(box,'@',1))<=64
        and box ~ '^[a-z0-9_+''-]+([.][a-z0-9_+''-]+)*@[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?([.][a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?)+$'
        and not club_private.is_usc_email(box) then box end
    from (select lower(regexp_replace(address,'^[[:space:]]+|[[:space:]]+$','','g')) as box) normalized
$$;
revoke all on function club_private.personal_mailbox(text) from public,anon,authenticated;
alter table club_private.alumni_invitations add constraint one_personal_mailbox
    check (club_private.personal_mailbox(email) is not distinct from email);

create or replace function club_private.invite_alumnus(c text,address text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare mailbox text := club_private.personal_mailbox(address); invitation club_private.alumni_invitations;
begin
    perform club_private.require_member(c,true);
    if mailbox is null then
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
