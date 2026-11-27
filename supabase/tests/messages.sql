-- All identities and messages exist only within this transaction.
begin;
set local plpgsql.check_asserts=on;
do $test$
declare
  a uuid:=gen_random_uuid(); b uuid:=gen_random_uuid(); stranger uuid:=gen_random_uuid(); outsider uuid:=gen_random_uuid();
  c text:='dm-'||gen_random_uuid(); other text:='dm-'||gen_random_uuid(); mid uuid:=gen_random_uuid();
  first_msg jsonb; p jsonb; cursor_id uuid; denied boolean; person uuid;
begin
  foreach person in array array[a,b,stranger,outsider] loop
    insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data)
      values(person,person::text||'@usc.edu',case when person=outsider then null else now() end,'{"provider":"email"}');
  end loop;
  insert into club_private.clubs(id,name,"fullName",about,"accentHex") values
    (c,'Fixture','Message fixture','','#445566'),(other,'Second','Other message fixture','','#445566');
  insert into club_private.members(club_id,id,name) values(c,a,'First'),(c,b,'Second'),(c,outsider,'Unverified'),
    (other,a,'First'),(other,b,'Second'),(other,stranger,'Stranger');
  set local role authenticated;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  first_msg:=public.send_message(c,b,mid,' hello ');
  assert first_msg->>'body'='hello' and first_msg->>'sender'=a::text and first_msg->>'id'=mid::text;
  assert public.send_message(c,b,mid,'hello')=first_msg,'Idempotent retry';
  p:=public.message_history(c,b); assert jsonb_array_length(p)=1 and p->0=first_msg;
  denied:=false; begin perform public.send_message(c,stranger,gen_random_uuid(),'out of club'); exception when insufficient_privilege then denied:=true; end;
  assert denied,'Contacts must be members of the same club';
  denied:=false; begin perform public.send_message(c,a,gen_random_uuid(),'self'); exception when insufficient_privilege then denied:=true; end;
  assert denied,'Self conversations are refused';
  denied:=false; begin perform public.send_message(c,b,mid,'changed text'); exception when invalid_parameter_value then denied:=true; end;
  assert denied,'A retry cannot change a message';
  p:=public.message_inbox(other); assert p='[]','Shared memberships must not merge conversations from different clubs';
  for i in 1..45 loop perform public.send_message(c,b,gen_random_uuid(),'Message '||i); end loop;
  p:=public.message_history(c,b); assert jsonb_array_length(p)=40;
  cursor_id:=(p->0->>'id')::uuid;
  assert jsonb_array_length(public.message_history(c,b,cursor_id,false))=6,'History loads older messages without overlap';
  assert jsonb_array_length(public.message_history(c,b,mid,true))=40;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',b,'role','authenticated')::text,true);
  p:=public.message_inbox(c); assert jsonb_array_length(p)=1 and (p->0->>'unread')::int=46;
  perform public.read_messages(c,a,(p->0->'latest'->>'id')::uuid);
  assert (public.message_inbox(c)->0->>'unread')::int=0,'Reading a conversation clears unread count';
  perform public.send_message(c,a,gen_random_uuid(),'Reply');
  perform set_config('request.jwt.claims',jsonb_build_object('sub',stranger,'role','authenticated')::text,true);
  denied:=false; begin perform public.message_history(c,a); exception when insufficient_privilege then denied:=true; end;
  assert denied,'A nonmember cannot read a conversation';
  assert public.message_history(other,a)='[]' and public.message_inbox(other)='[]','Private thread invisible to third parties';
  perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider,'role','authenticated')::text,true);
  denied:=false; begin perform public.message_inbox(c); exception when invalid_authorization_specification then denied:=true; end;
  assert denied,'Legacy membership cannot bypass USC verification';
  reset role;
  -- A full inbox also uses a two-column cursor when timestamps coincide.
  for i in 1..41 loop
    person:=gen_random_uuid();
    insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data)
        values(person,person::text||'@usc.edu',now(),'{"provider":"email"}');
    insert into club_private.members(club_id,id,name) values(c,person,'Fixture peer');
    insert into club_private.messages(id,club_id,sender,recipient,body,sent_at)
        values(gen_random_uuid(),c,person,a,'Inbox fixture',now()+interval '1 hour');
  end loop;
  set local role authenticated;
  perform set_config('request.jwt.claims',jsonb_build_object('sub',a,'role','authenticated')::text,true);
  p:=public.message_inbox(c); assert jsonb_array_length(p)=40;
  cursor_id:=(p->39->'latest'->>'id')::uuid;
  assert jsonb_array_length(public.message_inbox(c,cursor_id))=2,'Inbox paginates with tied timestamps';
  reset role;
  assert not has_table_privilege('authenticated','club_private.messages','select');
  assert not has_table_privilege('anon','club_private.messages','insert');
  assert not has_function_privilege('anon','public.message_inbox(text,uuid)','execute');
end $test$;
rollback;
