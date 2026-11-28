-- Membership now verifies either the USC identity or the accepted club-specific alumni invitation.
create or replace function club_private.require_message_peer(c text, peer uuid) returns void
language plpgsql stable security definer set search_path='' as $$
begin
    perform club_private.require_member(c);
    if peer is null or peer=auth.uid() or not exists (select from club_private.members where club_id=c and id=peer) then
        raise exception 'Choose another member of this club.' using errcode='42501';
    end if;
end $$;

create or replace function club_private.message_inbox(c text,cursor_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare myself uuid:=auth.uid(); boundary timestamptz;
begin
    perform club_private.require_member(c);
    if cursor_id is not null then
        select sent_at into boundary from club_private.messages where id=cursor_id and club_id=c and myself in (sender,recipient);
        if not found then raise exception 'Inbox position is unavailable.' using errcode='22023'; end if;
    end if;
    return coalesce((select jsonb_agg(jsonb_build_object('peer',p.peer,'latest',club_private.message_json(p.msg),'unread',p.unread)
            order by (p.msg).sent_at desc,(p.msg).id desc) from (
        select * from (
            select distinct on (peer) (case when m.sender=myself then m.recipient else m.sender end) as peer, m as msg,
                count(*) filter(where m.recipient=myself and m.read_at is null) over
                    (partition by case when m.sender=myself then m.recipient else m.sender end) as unread
            from club_private.messages m where m.club_id=c and myself in (m.sender,m.recipient)
            order by peer, m.sent_at desc, m.id desc
        ) latest where cursor_id is null or ((latest.msg).sent_at,(latest.msg).id)<(boundary,cursor_id)
        order by (latest.msg).sent_at desc,(latest.msg).id desc limit 40
    ) p), '[]');
end $$;
