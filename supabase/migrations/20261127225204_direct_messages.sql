-- A conversation belongs to one club even when both people belong to several.
create table club_private.messages (
    id uuid primary key,
    club_id text not null,
    sender uuid not null,
    recipient uuid not null,
    body text not null check (length(btrim(body)) between 1 and 4000),
    sent_at timestamptz not null default clock_timestamp(),
    read_at timestamptz,
    check (sender <> recipient),
    foreign key (club_id, sender) references club_private.members(club_id,id) on delete cascade,
    foreign key (club_id, recipient) references club_private.members(club_id,id) on delete cascade
);
create index messages_by_sender on club_private.messages(club_id, sender, recipient, sent_at desc, id desc);
create index messages_by_recipient on club_private.messages(club_id, recipient, sender, sent_at desc, id desc);
alter table club_private.messages enable row level security;
revoke all on club_private.messages from public, anon, authenticated;

create function club_private.require_message_peer(c text, peer uuid) returns void
language plpgsql stable security definer set search_path='' as $$
begin
    perform club_private.require_usc();
    perform club_private.require_member(c);
    if peer is null or peer=auth.uid() or not exists (select from club_private.members where club_id=c and id=peer) then
        raise exception 'Choose another member of this club.' using errcode='42501';
    end if;
end $$;

create function club_private.message_json(m club_private.messages) returns jsonb
language sql immutable set search_path='' as $$
    select jsonb_build_object('id',m.id,'sender',m.sender,'recipient',m.recipient,'body',m.body,'sentAt',m.sent_at,'readAt',m.read_at)
$$;

create function club_private.send_message(c text,peer uuid,message_id uuid,content text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare m club_private.messages;
begin
    perform club_private.require_message_peer(c,peer);
    if message_id is null or content is null or length(btrim(content)) not between 1 and 4000 then
        raise exception 'Enter a message of up to 4,000 characters.' using errcode='22023';
    end if;
    insert into club_private.messages(id,club_id,sender,recipient,body)
        values(message_id,c,auth.uid(),peer,btrim(content)) on conflict(id) do nothing returning * into m;
    if not found then
        -- A lost response can be retried with the same message ID and body.
        select * into m from club_private.messages where id=message_id and club_id=c and sender=auth.uid() and recipient=peer and body=btrim(content);
        if not found then raise exception 'Message could not be sent.' using errcode='22023'; end if;
    end if;
    return club_private.message_json(m);
end $$;

create function club_private.message_history(c text,peer uuid,cursor_id uuid,newer boolean) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare myself uuid:=auth.uid(); boundary timestamptz;
begin
    perform club_private.require_message_peer(c,peer);
    if cursor_id is not null then
        select sent_at into boundary from club_private.messages
            where id=cursor_id and club_id=c and ((sender=myself and recipient=peer) or (sender=peer and recipient=myself));
        if not found then raise exception 'Conversation position is unavailable.' using errcode='22023'; end if;
    end if;
    return coalesce((select jsonb_agg(club_private.message_json(page) order by page.sent_at,page.id) from (
        select m.* from club_private.messages m where m.club_id=c and
            ((m.sender=myself and m.recipient=peer) or (m.sender=peer and m.recipient=myself)) and
            (cursor_id is null or (newer and (m.sent_at,m.id)>(boundary,cursor_id))
                or (not newer and (m.sent_at,m.id)<(boundary,cursor_id)))
        order by case when newer then m.sent_at end asc, case when newer then m.id end asc,
            case when not newer then m.sent_at end desc, case when not newer then m.id end desc limit 40
    ) page), '[]');
end $$;

create function club_private.message_inbox(c text,cursor_id uuid) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare myself uuid:=auth.uid(); boundary timestamptz;
begin
    perform club_private.require_usc();
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

create function club_private.read_messages(c text,peer uuid,through_id uuid) returns void
language plpgsql security definer set search_path='' as $$
declare myself uuid:=auth.uid(); boundary timestamptz;
begin
    perform club_private.require_message_peer(c,peer);
    select sent_at into boundary from club_private.messages where id=through_id and club_id=c
        and ((sender=myself and recipient=peer) or (sender=peer and recipient=myself));
    if boundary is null then raise exception 'Conversation position is unavailable.' using errcode='22023'; end if;
    update club_private.messages set read_at=now()
        where club_id=c and sender=peer and recipient=myself and read_at is null and (sent_at,id)<=(boundary,through_id);
end $$;

create function public.message_inbox(c text,cursor_id uuid default null) returns jsonb language sql stable set search_path=''
as $$ select club_private.message_inbox(c,cursor_id) $$;
create function public.message_history(c text,peer uuid,cursor_id uuid default null,newer boolean default false) returns jsonb language sql stable set search_path=''
as $$ select club_private.message_history(c,peer,cursor_id,newer) $$;
create function public.send_message(c text,peer uuid,message_id uuid,content text) returns jsonb language sql set search_path=''
as $$ select club_private.send_message(c,peer,message_id,content) $$;
create function public.read_messages(c text,peer uuid,through_id uuid) returns void language sql set search_path=''
as $$ select club_private.read_messages(c,peer,through_id) $$;

create function public.verify_wallet_member() returns boolean language plpgsql stable set search_path='' as $$
begin perform club_private.require_usc(); return true; end $$;

do $$
declare fn regprocedure;
begin
    foreach fn in array array[
        'club_private.require_message_peer(text,uuid)'::regprocedure,'club_private.message_json(club_private.messages)'::regprocedure,
        'club_private.message_inbox(text,uuid)'::regprocedure,'club_private.message_history(text,uuid,uuid,boolean)'::regprocedure,
        'club_private.send_message(text,uuid,uuid,text)'::regprocedure,'club_private.read_messages(text,uuid,uuid)'::regprocedure,
        'public.message_inbox(text,uuid)'::regprocedure,'public.message_history(text,uuid,uuid,boolean)'::regprocedure,
        'public.send_message(text,uuid,uuid,text)'::regprocedure,'public.read_messages(text,uuid,uuid)'::regprocedure,
        'public.verify_wallet_member()'::regprocedure
    ] loop
        execute format('revoke all on function %s from public, anon',fn);
        execute format('grant execute on function %s to authenticated',fn);
    end loop;
end $$;
