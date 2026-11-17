-- Execute only inside BEGIN / ROLLBACK. No test record is kept.
do $$
declare u uuid;pid uuid;cid uuid;rev bigint;vkey uuid=gen_random_uuid();paykey uuid=gen_random_uuid();r jsonb;r2 jsonb;sale uuid;inst uuid;p jsonb;oldid uuid;qty integer;
begin
 for u in select id from auth.users where email_confirmed_at is not null order by created_at loop perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);exit when public.km_autorizado();end loop;
 pid=public.kmuv2_save_model(jsonb_build_object('kind','apparel','brand','Nike','model','Ignite Training','size','M','price',100,'cost',40,'stock',3,'photo','https://xzcwmhrdfueutareqxjw.supabase.co/storage/v1/object/public/kmuv2-photos/test.png'));
 r=public.kmuv2_business_command(gen_random_uuid(),'client','{"name":"Cliente de teste","phone":"","notes":"Teste"}');cid=(r->>'id')::uuid;
 p=jsonb_build_object('client',cid,'date',(now() at time zone 'America/Sao_Paulo')::date,'discount',0,'entry',0,'paymentConfirmed',false,'due',(now() at time zone 'America/Sao_Paulo')::date,'notes','Teste reversível','items',jsonb_build_array(jsonb_build_object('id',pid,'quantity',1,'price',100,'revision',1)));
 r=public.kmuv2_business_command(vkey,'sale',p);r2=public.kmuv2_business_command(vkey,'sale',p);sale=(r->>'venda_id')::uuid;
 if sale is null or r<>r2 or (select estoque_atual from public.kmb_produtos where id=pid)<>2 then raise exception 'Sale idempotency or inventory failed';end if;
 if exists(select 1 from public.kmb_pagamentos where venda_id=sale) then raise exception 'Payment created without confirmation';end if;
 select id into inst from public.kmb_parcelas where venda_id=sale;
 p=jsonb_build_object('installment',inst,'amount',25,'method','pix','date',(now() at time zone 'America/Sao_Paulo')::date,'confirmed',true);
 r=public.kmuv2_business_command(paykey,'payment',p);r2=public.kmuv2_business_command(paykey,'payment',p);
 if r<>r2 or (select sum(valor) from public.kmb_pagamentos where venda_id=sale)<>25 then raise exception 'Receipt idempotency failed';end if;
 select revision into rev from public.kmuv2_models where product_id=pid;
 r=public.kmuv2_business_command(gen_random_uuid(),'stock',jsonb_build_object('id',pid,'revision',rev,'mode','entrada','quantity',2,'reason','Reposição teste'));
 if (r->>'stock')::integer<>4 then raise exception 'Stock entry failed';end if;
 begin perform public.kmuv2_business_command(gen_random_uuid(),'stock',jsonb_build_object('id',pid,'revision',rev,'mode','entrada','quantity',2,'reason','Reposição teste'));raise exception 'Stale count accepted';exception when others then if sqlerrm='Stale count accepted' then raise;end if;end;
 r=public.kmuv2_business_command(gen_random_uuid(),'expense',jsonb_build_object('description','Despesa teste','amount',10,'date',(now() at time zone 'America/Sao_Paulo')::date));
 r=public.kmuv2_business_command(gen_random_uuid(),'task',jsonb_build_object('title','Retorno teste','date',(now() at time zone 'America/Sao_Paulo')::date));
 r=public.kmuv2_business_data();if jsonb_array_length(r->'sales')<1 or jsonb_array_length(r->'clients')<1 or jsonb_array_length(r->'expenses')<1 or jsonb_array_length(r->'archives')<>1 then raise exception 'Scoped business data failed';end if;
 select id into oldid from public.kmb_produtos where id not in(select product_id from public.kmuv2_models) limit 1;
 begin perform public.kmuv2_business_command(gen_random_uuid(),'stock',jsonb_build_object('id',oldid,'revision',1,'mode','entrada','quantity',2,'reason','Teste isolamento'));raise exception 'Historical stock changed';exception when others then if sqlerrm='Historical stock changed' then raise;end if;end;
 perform set_config('request.jwt.claims','{"role":"anon"}',true);
 begin perform public.kmuv2_business_data();raise exception 'Anonymous data exposed';exception when others then if sqlerrm='Anonymous data exposed' then raise;end if;end;
end $$;
