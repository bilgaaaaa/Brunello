-- Access-rule tests: three people (A creates the pet, B joins, C is a stranger) try everything.
-- Run by tests/run.sh against a throwaway Postgres with the real migration applied.
\set ON_ERROR_STOP on
\set QUIET on
insert into auth.users (id) values ('aaaaaaaa-0000-0000-0000-000000000001'), ('bbbbbbbb-0000-0000-0000-000000000002'), ('cccccccc-0000-0000-0000-000000000003');

-- Runs a statement as one signed-in person and reports whether it worked.
create or replace function pg_temp.try_as(user_id text, label text, statement text, expect text) returns void language plpgsql as $$
declare outcome text; affected bigint;
begin
  begin
    perform set_config('request.jwt.claim.sub', user_id, true);
    execute 'set local role ' || case when user_id = '' then 'anon' else 'authenticated' end;
    execute statement;
    get diagnostics affected = row_count;
    outcome := 'ok:' || affected;
  exception when others then
    outcome := 'error:' || sqlerrm;
  end;
  reset role;
  if outcome like expect then raise notice 'PASS  %  (%)', label, outcome;
  else raise exception 'FAIL  %  expected % got %', label, expect, outcome; end if;
end $$;

\set A '''aaaaaaaa-0000-0000-0000-000000000001'''
\set B '''bbbbbbbb-0000-0000-0000-000000000002'''
\set C '''cccccccc-0000-0000-0000-000000000003'''

select pg_temp.try_as('', 'anon cannot create a pet', $$select public.create_pet('Bruno','dog','EUR','X','Y')$$, 'error:permission denied%');
select pg_temp.try_as(:A, 'A creates Bruno', $$select public.create_pet(' Bruno ','dog','eur','Sofia','Mama')$$, 'ok:1');
select pg_temp.try_as(:A, 'A cannot create a second pet', $$select public.create_pet('Rex','dog','EUR','Sofia','Mama')$$, 'error:already_in_family');
select pg_temp.try_as(:A, 'A sees exactly one pet', $q$do $do$ begin if (select count(*) from public.pets) <> 1 then raise exception 'count'; end if; end $do$$q$, 'ok:%');
select pg_temp.try_as(:C, 'C sees no pets', $q$do $do$ begin if (select count(*) from public.pets) <> 0 then raise exception 'leak'; end if; end $do$$q$, 'ok:%');
select pg_temp.try_as(:B, 'wrong code is rejected', $$select public.join_pet('ZZZZZZ','Marco','Papà')$$, 'error:invite_not_found');

select invite_code as code, id as pet_id from public.pets \gset
select id as parent_a from public.parents where user_id = :A \gset
select format($$select public.join_pet('%s-%s','Marco','Papà')$$, lower(substr(:'code',1,3)), lower(substr(:'code',4,3))) as join_sql \gset
select pg_temp.try_as(:B, 'B joins with a lowercase dashed code', :'join_sql', 'ok:1');
select pg_temp.try_as(:B, 'B joining again is harmless', :'join_sql', 'ok:1');
select pg_temp.try_as(:C, 'C cannot join a full family', :'join_sql', 'error:family_full');
select id as parent_b from public.parents where user_id = :B \gset
select pg_temp.try_as(:B, 'B sees both parents', $q$do $do$ begin if (select count(*) from public.parents) <> 2 then raise exception 'count'; end if; end $do$$q$, 'ok:%');

select pg_temp.try_as(:A, 'A logs food', format($$insert into public.entries (pet_id, parent_id, kind, detail) values ('%s','%s','food','all')$$, :'pet_id', :'parent_a'), 'ok:1');
select pg_temp.try_as(:A, 'poo needs a detail', format($$insert into public.entries (pet_id, parent_id, kind) values ('%s','%s','poo')$$, :'pet_id', :'parent_a'), 'error:%entries_kind_detail_check%');
select pg_temp.try_as(:A, 'detail must fit the kind', format($$insert into public.entries (pet_id, parent_id, kind, detail) values ('%s','%s','pee','good')$$, :'pet_id', :'parent_a'), 'error:%entries_kind_detail_check%');
select pg_temp.try_as(:A, 'photo needs a file', format($$insert into public.entries (pet_id, parent_id, kind) values ('%s','%s','photo')$$, :'pet_id', :'parent_a'), 'error:%entries_photo_path_check%');
select pg_temp.try_as(:A, 'only photos carry a file', format($$insert into public.entries (pet_id, parent_id, kind, detail, photo_path) values ('%s','%s','poo','good','x.jpg')$$, :'pet_id', :'parent_a'), 'error:%entries_photo_path_check%');
select pg_temp.try_as(:A, 'A logs a photo', format($$insert into public.entries (pet_id, parent_id, kind, photo_path) values ('%s','%s','photo','%s/a.jpg')$$, :'pet_id', :'parent_a', :'pet_id'), 'ok:1');
select pg_temp.try_as(:B, 'B logs a walk', format($$insert into public.entries (pet_id, parent_id, kind, detail) values ('%s','%s','walk','long')$$, :'pet_id', :'parent_b'), 'ok:1');
select pg_temp.try_as(:B, 'B cannot log as A', format($$insert into public.entries (pet_id, parent_id, kind, detail) values ('%s','%s','pee','normal')$$, :'pet_id', :'parent_a'), 'error:new row violates row-level security%');
select pg_temp.try_as(:C, 'C cannot log at all', format($$insert into public.entries (pet_id, parent_id, kind, detail) values ('%s','%s','pee','normal')$$, :'pet_id', :'parent_a'), 'error:new row violates row-level security%');
select pg_temp.try_as(:B, 'B reads the whole diary', $q$do $do$ begin if (select count(*) from public.entries) <> 3 then raise exception 'count'; end if; end $do$$q$, 'ok:%');
select pg_temp.try_as(:C, 'C reads nothing', $q$do $do$ begin if (select count(*) from public.entries) + (select count(*) from public.parents) <> 0 then raise exception 'leak'; end if; end $do$$q$, 'ok:%');
select pg_temp.try_as(:B, 'B cannot delete entries by A', format($$delete from public.entries where parent_id = '%s'$$, :'parent_a'), 'ok:0');
select pg_temp.try_as(:A, 'A deletes own entry', format($$delete from public.entries where parent_id = '%s' and kind = 'food'$$, :'parent_a'), 'ok:1');
select pg_temp.try_as(:A, 'entries cannot be edited', $$update public.entries set detail = 'half'$$, 'error:permission denied%');

select pg_temp.try_as(:A, 'A logs an expense', format($$insert into public.expenses (pet_id, parent_id, category, amount_cents, owed_cents) values ('%s','%s','vet',8050,4025)$$, :'pet_id', :'parent_a'), 'ok:1');
select pg_temp.try_as(:B, 'B pays A back', format($$insert into public.expenses (pet_id, parent_id, category, amount_cents, owed_cents) values ('%s','%s','settle_up',4025,4025)$$, :'pet_id', :'parent_b'), 'ok:1');
select pg_temp.try_as(:B, 'B cannot log an expense as A', format($$insert into public.expenses (pet_id, parent_id, category, amount_cents, owed_cents) values ('%s','%s','food',100,50)$$, :'pet_id', :'parent_a'), 'error:new row violates row-level security%');
select pg_temp.try_as(:C, 'C cannot log an expense', format($$insert into public.expenses (pet_id, parent_id, category, amount_cents, owed_cents) values ('%s','%s','food',100,50)$$, :'pet_id', :'parent_a'), 'error:new row violates row-level security%');
select pg_temp.try_as(:A, 'amounts must be positive', format($$insert into public.expenses (pet_id, parent_id, category, amount_cents, owed_cents) values ('%s','%s','food',0,0)$$, :'pet_id', :'parent_a'), 'error:%expenses_amount_cents_check%');
select pg_temp.try_as(:A, 'the other parent can owe all of it', format($$insert into public.expenses (pet_id, parent_id, category, amount_cents, owed_cents) values ('%s','%s','toys',900,900)$$, :'pet_id', :'parent_a'), 'ok:1');
select pg_temp.try_as(:A, 'an expense can be unshared', format($$insert into public.expenses (pet_id, parent_id, category, amount_cents, owed_cents) values ('%s','%s','toys',900,0)$$, :'pet_id', :'parent_a'), 'ok:1');
select pg_temp.try_as(:A, 'nobody can owe more than the amount', format($$insert into public.expenses (pet_id, parent_id, category, amount_cents, owed_cents) values ('%s','%s','food',100,101)$$, :'pet_id', :'parent_a'), 'error:%expenses_owed_cents_check%');
select pg_temp.try_as(:A, 'a payback counts in full', format($$insert into public.expenses (pet_id, parent_id, category, amount_cents, owed_cents) values ('%s','%s','settle_up',100,50)$$, :'pet_id', :'parent_a'), 'error:%expenses_settle_up_check%');
select pg_temp.try_as(:A, 'categories are fixed', format($$insert into public.expenses (pet_id, parent_id, category, amount_cents, owed_cents) values ('%s','%s','party',100,50)$$, :'pet_id', :'parent_a'), 'error:%expenses_category_check%');
select pg_temp.try_as(:B, 'B reads every expense', $q$do $do$ begin if (select count(*) from public.expenses) <> 4 then raise exception 'count'; end if; end $do$$q$, 'ok:%');
select pg_temp.try_as(:C, 'C reads no expenses', $q$do $do$ begin if (select count(*) from public.expenses) <> 0 then raise exception 'leak'; end if; end $do$$q$, 'ok:%');
select pg_temp.try_as(:B, 'B cannot delete expenses by A', format($$delete from public.expenses where parent_id = '%s'$$, :'parent_a'), 'ok:0');
select pg_temp.try_as(:A, 'expenses cannot be edited', $$update public.expenses set amount_cents = 1$$, 'error:permission denied%');
select pg_temp.try_as(:A, 'A deletes own expenses', format($$delete from public.expenses where parent_id = '%s'$$, :'parent_a'), 'ok:3');
select pg_temp.try_as(:A, 'A changes the currency', $$update public.pets set currency_code = 'GBP'$$, 'ok:1');
select pg_temp.try_as(:A, 'currency codes are three capital letters', $$update public.pets set currency_code = 'euro'$$, 'error:%pets_currency_code_check%');

select pg_temp.try_as(:A, 'A renames the pet', $$update public.pets set name = 'Brunello', species = 'cat'$$, 'ok:1');
select pg_temp.try_as(:A, 'invite code cannot be changed', $$update public.pets set invite_code = 'AAAAAA'$$, 'error:permission denied%');
select pg_temp.try_as(:C, 'C cannot rename the pet', $$update public.pets set name = 'Hacked'$$, 'ok:0');
select pg_temp.try_as(:B, 'B changes own nickname', format($$update public.parents set nickname = 'Daddy' where id = '%s'$$, :'parent_b'), 'ok:1');
select pg_temp.try_as(:B, 'B cannot rename A', format($$update public.parents set name = 'Nope' where id = '%s'$$, :'parent_a'), 'ok:0');
select pg_temp.try_as(:B, 'names are capped at 12 letters', format($$update public.parents set name = 'This is far too long' where id = '%s'$$, :'parent_b'), 'error:%parents_name_check%');
select pg_temp.try_as(:B, 'B cannot move to another pet', format($$update public.parents set pet_id = gen_random_uuid() where id = '%s'$$, :'parent_b'), 'error:permission denied%');

select pg_temp.try_as(:A, 'A saves a push token', $$select public.save_device_token(repeat('ab', 32), 'sandbox')$$, 'ok:1');
select pg_temp.try_as(:B, 'same phone, new person takes the token over', $$select public.save_device_token(repeat('ab', 32), 'production')$$, 'ok:1');
select pg_temp.try_as(:A, 'bad tokens are refused', $$select public.save_device_token('not-a-token', 'sandbox')$$, 'error:%device_tokens_token_check%');
select pg_temp.try_as(:A, 'tokens are not readable from the app', $$select * from public.device_tokens$$, 'error:permission denied%');
select pg_temp.try_as(:A, 'invite generator is private', $$select public.generate_invite_code()$$, 'error:permission denied%');

select pg_temp.try_as(:A, 'A uploads into the pet folder', format($$insert into storage.objects (bucket_id, name, owner_id) values ('photos', '%s/a.jpg', 'aaaaaaaa-0000-0000-0000-000000000001')$$, :'pet_id'), 'ok:1');
select pg_temp.try_as(:B, 'B can view the photo', $q$do $do$ begin if (select count(*) from storage.objects) <> 1 then raise exception 'count'; end if; end $do$$q$, 'ok:%');
select pg_temp.try_as(:C, 'C cannot upload into the pet folder', format($$insert into storage.objects (bucket_id, name, owner_id) values ('photos', '%s/c.jpg', 'cccccccc-0000-0000-0000-000000000003')$$, :'pet_id'), 'error:new row violates row-level security%');
select pg_temp.try_as(:C, 'C cannot view photos', format($q$do $do$ begin if (select count(*) from storage.objects where name like '%s/%%') <> 0 then raise exception 'leak'; end if; end $do$$q$, :'pet_id'), 'ok:%');
select pg_temp.try_as(:B, 'B cannot delete a photo by A', $$delete from storage.objects$$, 'ok:0');
select pg_temp.try_as(:A, 'A deletes own photo', $$delete from storage.objects$$, 'ok:1');

do $$ begin
  if (select user_id from public.device_tokens) <> 'bbbbbbbb-0000-0000-0000-000000000002' then raise exception 'FAIL token owner'; end if;
  if (select name from public.pets) <> 'Brunello' then raise exception 'FAIL pet name'; end if;
  if (select currency_code from public.pets) <> 'GBP' then raise exception 'FAIL currency'; end if;
  if (select invite_code from public.pets) !~ '^[A-HJKMNP-Z2-9]{6}$' then raise exception 'FAIL invite code shape'; end if;
  raise notice 'PASS  final state checks';
end $$;
