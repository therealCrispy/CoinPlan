-- Synthetic, transaction-scoped fixtures. No existing data is changed.
begin;
insert into auth.users(id) values ('4f9d9e6f-0068-44c6-bb56-c64b60a89101'),('4f9d9e6f-0068-44c6-bb56-c64b60a89102');
insert into public.coinplan_bank_items(id,owner,token,institution) values('coinplan-test-item','4f9d9e6f-0068-44c6-bb56-c64b60a89101','synthetic-cipher','Simulated bank');
set local role authenticated;
select set_config('request.jwt.claim.sub','4f9d9e6f-0068-44c6-bb56-c64b60a89101',true);
do $$ declare rev bigint; caught boolean:=false;
begin
 select public.coinplan_save_state('{"version":2,"transactions":[]}',0) into rev;
 if rev<>1 then raise exception 'First cloud save failed';end if;
 select public.coinplan_save_state('{"version":2,"transactions":[]}',1) into rev;
 if rev<>2 then raise exception 'Cloud update failed';end if;
 begin perform public.coinplan_save_state('{"version":2,"transactions":[]}',1);exception when others then caught:=true;end;
 if not caught then raise exception 'Stale cloud revision accepted';end if;
end $$;
reset role;
set local role service_role;
do $$ declare result jsonb;
begin
 select public.coinplan_bank_lease('coinplan-test-item','4f9d9e6f-0068-44c6-bb56-c64b60a89102','4f9d9e6f-0068-44c6-bb56-c64b60a89103') into result;
 if result is not null then raise exception 'Wrong owner acquired lease';end if;
 select public.coinplan_bank_lease('coinplan-test-item','4f9d9e6f-0068-44c6-bb56-c64b60a89101','4f9d9e6f-0068-44c6-bb56-c64b60a89103') into result;
 if result is null then raise exception 'Own lease failed';end if;
 perform public.coinplan_bank_commit('coinplan-test-item','4f9d9e6f-0068-44c6-bb56-c64b60a89101','4f9d9e6f-0068-44c6-bb56-c64b60a89103','next-cursor','[{"id":"coinplan-test-account"}]','[{"id":"coinplan-test-transaction"}]','[]');
 if not exists(select 1 from public.coinplan_bank_items where id='coinplan-test-item' and cursor='next-cursor' and lease is null) then raise exception 'Atomic cursor/lease commit failed';end if;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','4f9d9e6f-0068-44c6-bb56-c64b60a89101',true);
do $$ declare n integer;
begin select count(*) into n from public.coinplan_bank_transactions; if n<>1 then raise exception 'Own bank read failed';end if;end $$;
select set_config('request.jwt.claim.sub','4f9d9e6f-0068-44c6-bb56-c64b60a89102',true);
do $$ declare n integer;
begin
 select count(*) into n from public.coinplan_state; if n<>0 then raise exception 'Cross-account cloud read allowed';end if;
 select count(*) into n from public.coinplan_bank_accounts; if n<>0 then raise exception 'Cross-account bank account read allowed';end if;
 select count(*) into n from public.coinplan_bank_transactions; if n<>0 then raise exception 'Cross-account transaction read allowed';end if;
 update public.coinplan_state set payload='{}';get diagnostics n=row_count;if n<>0 then raise exception 'Cross-account cloud write allowed';end if;
end $$;
reset role;
do $$ begin
 if has_table_privilege('anon','public.coinplan_state','SELECT') then raise exception 'Anonymous cloud read allowed';end if;
 if has_table_privilege('authenticated','public.coinplan_bank_items','SELECT') then raise exception 'Browser token read allowed';end if;
 if has_function_privilege('authenticated','public.coinplan_bank_lease(text,uuid,uuid)','EXECUTE') then raise exception 'Browser bank lease allowed';end if;
 if has_function_privilege('anon','public.coinplan_bank_commit(text,uuid,uuid,text,jsonb,jsonb,jsonb)','EXECUTE') then raise exception 'Anonymous bank commit allowed';end if;
end $$;
rollback;
select 'Passed: revisions, conflicts, account isolation, private token denial, atomic bank commit. All synthetic fixtures rolled back.' as acceptance;
