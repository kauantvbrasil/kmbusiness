-- Run only inside a transaction followed by ROLLBACK. Nothing is kept.
do $$
declare owner_id uuid;pid uuid;oid uuid;sale uuid;r jsonb;r2 jsonb;req jsonb;revision bigint;remaining integer;old_id uuid;
begin
 for owner_id in select id from auth.users where email_confirmed_at is not null order by created_at loop perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);exit when public.km_autorizado();end loop;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 pid=public.kmuv2_save_model(jsonb_build_object('kind','apparel','brand','Marca de teste','model','Modelo de teste','size','M','stock',3,'price',100,'cost',40,'photo','https://xzcwmhrdfueutareqxjw.supabase.co/storage/v1/object/public/kmuv2-photos/test.png'));
 req=jsonb_build_object('key',gen_random_uuid(),'name','Cliente de Teste','items',jsonb_build_array(jsonb_build_object('id',pid,'quantity',2,'price',100)),'mode','pickup','notes','Teste transacional');
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 r=public.kmuv2_create_order(req,repeat('a',64));r2=public.kmuv2_create_order(req,repeat('a',64));if r->>'id'<>r2->>'id' then raise exception 'Duplicate request was created';end if;oid=(r->>'id')::uuid;
 if (select estoque_atual from public.kmb_produtos where id=pid)<>3 then raise exception 'Request changed stock';end if;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 r=public.kmuv2_decide_order(oid,true,jsonb_build_object(pid::text,100),0,'',true);sale=(r->>'sale_id')::uuid;
 r2=public.kmuv2_decide_order(oid,true,jsonb_build_object(pid::text,100),0,'',true);
 if sale::text<>r2->>'sale_id' or (select estoque_atual from public.kmb_produtos where id=pid)<>1 then raise exception 'Double stock decrement';end if;
 if (select valor_total from public.kmb_vendas where id=sale)<>200 then raise exception 'Wrong financial total';end if;
 if exists(select 1 from public.kmb_pagamentos where venda_id=sale) then raise exception 'Payment must remain unconfirmed';end if;
 if (select sum(valor) from public.kmb_parcelas where venda_id=sale)<>200 then raise exception 'Incomplete receivable';end if;
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);
 req=jsonb_set(req,'{key}',to_jsonb(gen_random_uuid()));req=jsonb_set(req,'{items}',jsonb_build_array(jsonb_build_object('id',pid,'quantity',1,'price',100)));
 r=public.kmuv2_create_order(req,repeat('b',64));oid=(r->>'id')::uuid;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 perform public.kmuv2_decide_order(oid,false,'{}',null,'Teste de recusa',false);
 if (select estoque_atual from public.kmb_produtos where id=pid)<>1 or (select sale_id from public.kmuv2_orders where id=oid) is not null then raise exception 'Refusal mutated stock/finance';end if;
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 begin perform public.kmuv2_admin_data();raise exception 'Unauthorized access accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 select id into old_id from public.kmb_produtos where id<>pid order by criado_em limit 1;
 begin perform public.kmuv2_save_model(jsonb_build_object('id',old_id,'revision',1,'kind','apparel','brand','Marca','model','Modelo','size','M','stock',1,'price',10,'cost',1,'photo','https://xzcwmhrdfueutareqxjw.supabase.co/storage/v1/object/public/kmuv2-photos/test.png'));raise exception 'Historical product was included';exception when others then if sqlerrm='Historical product was included' then raise;end if;end;
end $$;
do $$
declare owner_id uuid;pid uuid;req jsonb;r jsonb;sale uuid;order_id uuid;n integer;
begin
 for owner_id in select id from auth.users where email_confirmed_at is not null order by created_at loop perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);exit when public.km_autorizado();end loop;perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 pid=public.kmuv2_save_model(jsonb_build_object('kind','apparel','brand','Marca de teste','model','Modelo entrega','size','G','stock',1,'price',100,'cost',40,'photo','https://xzcwmhrdfueutareqxjw.supabase.co/storage/v1/object/public/kmuv2-photos/test.png'));
 req=jsonb_build_object('key',gen_random_uuid(),'name','Cliente de Teste','items',jsonb_build_array(jsonb_build_object('id',pid,'quantity',1,'price',100)),'mode','delivery','address',jsonb_build_object('cep','00000000','street','Endereço de teste','number','1','reference','Teste'),'shipping',15);
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);r=public.kmuv2_create_order(req,repeat('c',64));order_id=(r->>'id')::uuid;
 perform set_config('request.jwt.claims',jsonb_build_object('sub',owner_id,'role','authenticated')::text,true);
 begin perform public.kmuv2_decide_order(order_id,true,jsonb_build_object(pid::text,90),15,'',true);raise exception 'Changed price accepted';exception when serialization_failure then null;end;
 if (select estoque_atual from public.kmb_produtos where id=pid)<>1 then raise exception 'Price conflict changed stock';end if;
 r=public.kmuv2_decide_order(order_id,true,jsonb_build_object(pid::text,100),15,'',true);sale=(r->>'sale_id')::uuid;
 if (select valor_total from public.kmb_vendas where id=sale)<>115 or (select sum(valor) from public.kmb_parcelas where venda_id=sale)<>115 or (select sum(quantidade*preco_unitario) from public.kmb_venda_itens where venda_id=sale)<>115 then raise exception 'Shipping was not reconciled with finance';end if;
 if exists(select 1 from public.kmb_pagamentos where venda_id=sale) then raise exception 'Shipping approval confirmed payment';end if;
 if (select estoque_atual from public.kmb_produtos where id=pid)<>0 then raise exception 'Stock was not decremented';end if;
 perform set_config('request.jwt.claims','{"role":"service_role"}',true);r=public.kmuv2_public_catalog();if exists(select 1 from jsonb_array_elements(r->'products')x where x->>'id'=pid::text and (x->>'available')::boolean) then raise exception 'Sold out product is still available';end if;
 if jsonb_array_length(r->'products')<>(select count(*) from public.kmuv2_models where visible) then raise exception 'Legacy products leaked into catalog';end if;
 perform public.kmuv2_event_batch(jsonb_build_object('batchId',gen_random_uuid(),'consent',false,'visitor','not-persisted','events',jsonb_build_array(jsonb_build_object('type','visit'),jsonb_build_object('type','search','term','PRIVATE NAME'))));
 if exists(select 1 from public.kmuv2_events where visitor='not-persisted') then raise exception 'Analytics collected without consent';end if;
end $$;
