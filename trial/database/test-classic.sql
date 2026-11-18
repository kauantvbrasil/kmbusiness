-- Execute only inside BEGIN / ROLLBACK.
do $$
declare u uuid;pid uuid;old_id uuid;k uuid=gen_random_uuid();p jsonb;r jsonb;r2 jsonb;sid uuid;version bigint;c integer;
begin
 for u in select id from auth.users where email_confirmed_at is not null order by created_at loop perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);exit when public.km_autorizado();end loop;
 pid=public.kmuv2_save_model(jsonb_build_object('kind','apparel','brand','Marca teste','model','Modelo teste','size','M','price',120,'cost',50,'stock',5,'photo','https://xzcwmhrdfueutareqxjw.supabase.co/storage/v1/object/public/kmuv2-photos/test.png'));
 p=jsonb_build_object('clientName','Cliente Teste','phone','','date',(now() at time zone 'America/Sao_Paulo')::date,'price',100,'discount',20,'paymentConfirmed',false,'method',null,'notes','Teste','owner','Admin teste','fees',2,'saleExpenses',1,'due',(now() at time zone 'America/Sao_Paulo')::date,'items',jsonb_build_array(jsonb_build_object('id',pid,'quantity',1,'price',120,'revision',1)),'plan',jsonb_build_array(jsonb_build_object('v',50,'d',(now() at time zone 'America/Sao_Paulo')::date,'paid',false),jsonb_build_object('v',50,'d',(now() at time zone 'America/Sao_Paulo')::date+30,'paid',false)));
 r=public.kmuv2_classic_sale(k,p);r2=public.kmuv2_classic_sale(k,p);sid=(r->>'venda_id')::uuid;
 if sid is null or r<>r2 or (select estoque_atual from public.kmb_produtos where id=pid)<>4 then raise exception 'Classic sale idempotency failed';end if;
 if (select count(*) from public.kmb_parcelas where venda_id=sid and status='pendente')<>2 or exists(select 1 from public.kmb_pagamentos where venda_id=sid) then raise exception 'Installments or unpaid status failed';end if;
 if not exists(select 1 from kmuv2_private.classic_records where id='sale_meta_'||sid and data->>'owner'='Admin teste') then raise exception 'Metadata missing';end if;
 select versao_edicao into version from public.kmb_vendas where id=sid;
 p=p||jsonb_build_object('cost',50,'price',100);
 r=public.kmuv2_classic_edit(gen_random_uuid(),sid,version,p);
 if (select valor_total from public.kmb_vendas where id=sid)<>100 or (select estoque_atual from public.kmb_produtos where id=pid)<>4 then raise exception 'Classic edit changed totals or stock incorrectly';end if;
 r=public.kmuv2_classic_stock(jsonb_build_object('id','classic-test-batch','kind','inbound','reason','Reposição teste','items',jsonb_build_array(jsonb_build_object('pid',pid,'qty',2,'cost',45))));r2=public.kmuv2_classic_stock(jsonb_build_object('id','classic-test-batch','kind','inbound','reason','Reposição teste','items',jsonb_build_array(jsonb_build_object('pid',pid,'qty',2,'cost',45))));
 if r<>r2 or (select estoque_atual from public.kmb_produtos where id=pid)<>6 then raise exception 'Classic batch stock duplicated';end if;
 r=public.kmuv2_classic_write('config','{"id":"test-settings","value":1}','');
 begin perform public.kmuv2_classic_write('config','{"id":"test-settings","value":2}','');raise exception 'Stale metadata overwrote current';exception when others then if sqlerrm='Stale metadata overwrote current' then raise;end if;end;
 select id into old_id from public.kmb_produtos where id not in(select product_id from public.kmuv2_models) limit 1;
 select count(*) into c from public.kmb_clientes;
 begin perform public.kmuv2_classic_sale(gen_random_uuid(),p||jsonb_build_object('items',jsonb_build_array(jsonb_build_object('id',old_id,'quantity',1,'price',100,'revision',1))));raise exception 'Historical item included';exception when others then if sqlerrm='Historical item included' then raise;end if;end;
 if (select count(*) from public.kmb_clientes)<>c then raise exception 'Rejected historical item still created client';end if;
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 begin perform public.kmuv2_classic_metadata();raise exception 'Anonymous metadata exposed';exception when others then if sqlerrm='Anonymous metadata exposed' then raise;end if;end;
end$$;
