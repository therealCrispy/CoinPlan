begin;
create table if not exists public.coinplan_state (
 owner uuid primary key references auth.users(id) on delete cascade,
 revision bigint not null default 1,
 payload jsonb not null check (octet_length(payload::text) < 10000000),
 updated_at timestamptz not null default now()
);
alter table public.coinplan_state enable row level security;
revoke all on public.coinplan_state from anon, authenticated;
grant select, insert, update on public.coinplan_state to authenticated;
create policy "Own plan" on public.coinplan_state for all to authenticated using (owner=auth.uid()) with check (owner=auth.uid());
create or replace function public.coinplan_save_state(p_payload jsonb,p_revision bigint) returns bigint language plpgsql security invoker set search_path='' as $$
declare next_revision bigint;
begin
 if auth.uid() is null then raise exception 'Sign in required'; end if;
 if p_payload->>'version'<>'2' or not (p_payload ? 'transactions') then raise exception 'Invalid plan'; end if;
 if p_revision=0 then
  insert into public.coinplan_state(owner,payload,revision) values(auth.uid(),p_payload,1) on conflict do nothing returning revision into next_revision;
 else
  update public.coinplan_state set payload=p_payload,revision=revision+1,updated_at=now() where owner=auth.uid() and revision=p_revision returning revision into next_revision;
 end if;
 if next_revision is null then raise exception 'Cloud plan changed. Reload the cloud plan before saving.'; end if;
 return next_revision;
end $$;
revoke all on function public.coinplan_save_state(jsonb,bigint) from public,anon;
grant execute on function public.coinplan_save_state(jsonb,bigint) to authenticated;
-- Tokens are encrypted again before storage. No browser role has table access.
create table public.coinplan_bank_items (
 id text primary key,
 owner uuid not null references auth.users(id) on delete cascade,
 token text not null,
 institution text not null,
 cursor text not null default '',
 lease uuid,
 lease_until timestamptz,
 updated_at timestamptz not null default now()
);
create table public.coinplan_bank_accounts (
 id text primary key,
 item_id text not null references public.coinplan_bank_items(id) on delete cascade,
 owner uuid not null references auth.users(id) on delete cascade,
 payload jsonb not null
);
create table public.coinplan_bank_transactions (
 id text primary key,
 item_id text not null references public.coinplan_bank_items(id) on delete cascade,
 owner uuid not null references auth.users(id) on delete cascade,
 payload jsonb not null
);
alter table public.coinplan_bank_items enable row level security;
alter table public.coinplan_bank_accounts enable row level security;
alter table public.coinplan_bank_transactions enable row level security;
revoke all on public.coinplan_bank_items,public.coinplan_bank_accounts,public.coinplan_bank_transactions from public,anon,authenticated;
grant all on public.coinplan_bank_items,public.coinplan_bank_accounts,public.coinplan_bank_transactions to service_role;
grant select on public.coinplan_bank_accounts,public.coinplan_bank_transactions to authenticated;
create policy "Own bank accounts" on public.coinplan_bank_accounts for select to authenticated using(owner=auth.uid());
create policy "Own bank transactions" on public.coinplan_bank_transactions for select to authenticated using(owner=auth.uid());
create function public.coinplan_bank_lease(p_item text,p_owner uuid,p_lease uuid) returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 update public.coinplan_bank_items set lease=p_lease,lease_until=now()+interval '5 minutes' where id=p_item and owner=p_owner and (lease_until is null or lease_until<now()) returning to_jsonb(coinplan_bank_items.*) into result;
 return result;
end $$;
create function public.coinplan_bank_commit(p_item text,p_owner uuid,p_lease uuid,p_cursor text,p_accounts jsonb,p_transactions jsonb,p_removed jsonb) returns boolean language plpgsql security definer set search_path='' as $$
declare record jsonb;
begin
 perform 1 from public.coinplan_bank_items where id=p_item and owner=p_owner and lease=p_lease and lease_until>now() for update;
 if not found then raise exception 'Bank sync lease expired'; end if;
 for record in select value from jsonb_array_elements(p_accounts) loop
  insert into public.coinplan_bank_accounts(id,item_id,owner,payload) values(record->>'id',p_item,p_owner,record)
  on conflict(id) do update set payload=excluded.payload where coinplan_bank_accounts.item_id=p_item and coinplan_bank_accounts.owner=p_owner;
 end loop;
 delete from public.coinplan_bank_transactions where item_id=p_item and owner=p_owner and id in(select value#>>'{}' from jsonb_array_elements(p_removed));
 for record in select value from jsonb_array_elements(p_transactions) loop
  insert into public.coinplan_bank_transactions(id,item_id,owner,payload) values(record->>'id',p_item,p_owner,record)
  on conflict(id) do update set payload=excluded.payload where coinplan_bank_transactions.item_id=p_item and coinplan_bank_transactions.owner=p_owner;
 end loop;
 update public.coinplan_bank_items set cursor=p_cursor,lease=null,lease_until=null,updated_at=now() where id=p_item and owner=p_owner;
 return true;
end $$;
revoke all on function public.coinplan_bank_lease(text,uuid,uuid),public.coinplan_bank_commit(text,uuid,uuid,text,jsonb,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.coinplan_bank_lease(text,uuid,uuid),public.coinplan_bank_commit(text,uuid,uuid,text,jsonb,jsonb,jsonb) to service_role;
commit;
