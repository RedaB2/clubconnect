-- Each member can listen on their own per-club topic. No client INSERT policy:
-- the database alone publishes invalidations, without message text or member IDs in the payload.
create function club_private.can_listen_to_mailbox(channel text) returns boolean
language plpgsql stable security definer set search_path='' as $$
begin
    perform club_private.require_usc();
    return exists (
        select from club_private.members m
        where m.id = (select auth.uid()) and channel = 'mail:' || m.id || ':' || m.club_id
    );
end $$;
revoke all on function club_private.can_listen_to_mailbox(text) from public,anon;
grant execute on function club_private.can_listen_to_mailbox(text) to authenticated;

create policy clubconnect_own_mailbox on realtime.messages for select to authenticated
using (extension = 'broadcast' and (select club_private.can_listen_to_mailbox((select realtime.topic()))));

create function club_private.signal_mailboxes() returns trigger
language plpgsql security definer set search_path='' as $$
declare mailbox record;
begin
    -- Read receipts can update many rows at once. Signal each affected inbox once.
    for mailbox in
        select sender as member, club_id from changed_messages
        union
        select recipient as member, club_id from changed_messages
    loop
        perform realtime.send('{}'::jsonb, 'changed', 'mail:' || mailbox.member || ':' || mailbox.club_id, true);
    end loop;
    return null;
end $$;
revoke all on function club_private.signal_mailboxes() from public,anon,authenticated;
create trigger message_added after insert on club_private.messages
    referencing new table as changed_messages for each statement execute function club_private.signal_mailboxes();
create trigger message_read after update on club_private.messages
    referencing new table as changed_messages for each statement execute function club_private.signal_mailboxes();
