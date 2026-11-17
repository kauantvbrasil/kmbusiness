create or replace function kmuv2_private.create_order(p jsonb,p_rate text) returns jsonb language plpgsql security definer set search_path='' as $$
declare existing public.kmuv2_orders%rowtype; pid uuid; item record; product public.kmb_produtos%rowtype; rows jsonb='[]'; total numeric=0; rate_n integer; hash text;begin
 perform kmuv2_private.authorize_service();
 if length(p_rate)<>64 or jsonb_array_length(p->'items') not between 1 and 30 or length(btrim(p->>'name')) not between 3 and 120 or length(coalesce(p->>'notes',''))>500 or p->>'mode' not in ('delivery','pickup') then raise exception 'Confira os dados da solicitação.';end if;
 hash=md5((p-'shipping')::text);
 perform pg_advisory_xact_lock(hashtextextended(p->>'key',0));
 select * into existing from public.kmuv2_orders where idempotency_key=(p->>'key')::uuid;
 if found then if existing.request_hash<>hash then raise exception 'Use uma nova chave para uma nova seleção.';end if;return jsonb_build_object('id',existing.id,'code',existing.code,'duplicate',true,'subtotal',existing.subtotal,'shipping',existing.shipping,'status',existing.status,'verified',false);end if;
 delete from kmuv2_private.rate_limits where expires_at<now();
 insert into kmuv2_private.rate_limits(key,n,expires_at) values(p_rate||':'||to_char(now(),'YYYY-MM-DD-HH24'),1,now()+interval '2 hours') on conflict(key) do update set n=kmuv2_private.rate_limits.n+1 returning n into rate_n;
 if rate_n>8 then raise exception 'Muitas solicitações. Aguarde antes de tentar novamente.';end if;
 for item in select * from jsonb_to_recordset(p->'items') as x(id uuid,quantity integer,price numeric,brand text,model text,size text) order by id loop
  if item.quantity is null or item.quantity not between 1 and 99 then raise exception 'Quantidade inválida.';end if;
  if exists(select 1 from jsonb_array_elements(rows)x where x->>'id'=item.id::text) then raise exception 'Modelo repetido na solicitação.';end if;
  select t.* into product from public.kmb_produtos t join public.kmuv2_models m on m.product_id=t.id where t.id=item.id and m.visible and m.operation_kind='apparel';
  if not found or not product.ativo or product.estoque_atual<item.quantity then raise exception 'Um modelo ficou indisponível. Revise a sacola.';end if;
  if (item.brand is not null and item.brand is distinct from product.marca) or (item.model is not null and item.model is distinct from product.modelo) or (item.size is not null and item.size is distinct from product.variacao) then raise exception 'Os detalhes mudaram. Atualize e revise a sacola.';end if;
  if item.price is distinct from product.preco_venda then raise exception 'Um valor mudou. Atualize e revise a sacola.';end if;
  total=total+product.preco_venda*item.quantity;
  rows=rows||jsonb_build_object('id',product.id,'brand',product.marca,'model',product.modelo,'size',product.variacao,'quantity',item.quantity,'price',product.preco_venda,'photo',product.foto_url);
 end loop;
 if p->>'mode'='delivery' and (jsonb_typeof(p->'address') is distinct from 'object' or length(p#>>'{address,cep}')<>8 or length(p#>>'{address,street}')<2 or length(p#>>'{address,number}')<1 or length(p#>>'{address,reference}')<1) then raise exception 'Endereço incompleto.';end if;
 insert into public.kmuv2_orders(idempotency_key,request_hash,customer_name,items,subtotal,mode,address,shipping,notes) values((p->>'key')::uuid,hash,btrim(p->>'name'),rows,total,p->>'mode',case when p->>'mode'='delivery' then p->'address' else null end,case when p->>'mode'='pickup' then 0 else (p->>'shipping')::numeric end,coalesce(p->>'notes','')) returning * into existing;
 return jsonb_build_object('id',existing.id,'code',existing.code,'subtotal',existing.subtotal,'shipping',existing.shipping,'status','pending','verified',false);end $$;
create or replace function kmuv2_private.decide_order(p_id uuid,p_accept boolean,p_prices jsonb,p_shipping numeric,p_reason text,p_contact boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.kmuv2_orders%rowtype; row record; product public.kmb_produtos%rowtype; rows jsonb='[]'; customer uuid; result jsonb; sale uuid; v_subtotal numeric=0; fee numeric; old_guc text;begin
 perform kmuv2_private.authorize_admin();select * into o from public.kmuv2_orders where id=p_id for update;
 if not found then raise exception 'Solicitação não encontrada.';end if;
 if o.status='accepted' then if p_accept then return jsonb_build_object('sale_id',o.sale_id,'duplicate',true);else raise exception 'Solicitação já aceita.';end if;end if;
 if o.status<>'pending' then raise exception 'Solicitação já encerrada.';end if;
 if not p_accept then update public.kmuv2_orders set status='refused',reason=left(coalesce(p_reason,''),500),decided_at=now(),decided_by=auth.uid() where id=p_id;return jsonb_build_object('status','refused');end if;
 if p_contact is distinct from true then raise exception 'Confirme o contato com o cliente antes de aceitar.';end if;
 if o.created_at<now()-interval '7 days' then raise exception 'A solicitação venceu. Peça uma nova revisão ao cliente.';end if;
 fee=case when o.mode='pickup' then 0 else coalesce(p_shipping,o.shipping) end;
 if fee is null or fee<0 or round(fee,2)<>fee then raise exception 'Confira o valor da entrega antes de aceitar.';end if;
 for row in select * from jsonb_to_recordset(o.items) as x(id uuid,quantity integer,price numeric,brand text,model text,size text) order by id loop
  perform 1 from public.kmuv2_models where product_id=row.id and visible and operation_kind='apparel' for update;if not found then raise exception 'Modelo fora da operação atual.';end if;
  select * into product from public.kmb_produtos where id=row.id for update;
  if not product.ativo or product.estoque_atual<row.quantity then raise exception 'Estoque insuficiente. Nenhuma venda foi registrada.';end if;
  if row.brand is distinct from product.marca or row.model is distinct from product.modelo or row.size is distinct from product.variacao then raise exception 'Os detalhes do modelo mudaram. Peça uma nova revisão ao cliente.' using errcode='40001';end if;
  if (p_prices->>row.id::text)::numeric is distinct from product.preco_venda then raise exception 'Os valores mudaram. Reabra e confira a solicitação.' using errcode='40001';end if;
  rows=rows||jsonb_build_object('produto_id',row.id,'quantidade',row.quantity);v_subtotal=v_subtotal+row.quantity*product.preco_venda;
 end loop;
 insert into public.kmb_clientes(nome,observacoes) values(o.customer_name,'Solicitação '||o.code) returning id into customer;
 result=public.kmb_confirmar_venda_expressa(p_chave_operacao=>o.id,p_itens=>rows,p_cliente_id=>customer,p_data_venda=>(now() at time zone 'America/Sao_Paulo')::date,p_entrada=>0,p_vencimento=>(now() at time zone 'America/Sao_Paulo')::date,p_observacoes=>o.code||' · '||o.notes);
 sale=(result->>'venda_id')::uuid;update public.kmuv2_models set revision=revision+1 where product_id in (select (x->>'id')::uuid from jsonb_array_elements(o.items)x);
 if fee>0 then
  insert into public.kmb_venda_itens(venda_id,descricao,quantidade,preco_unitario,custo_unitario) values(sale,'Entrega',1,fee,0);
  old_guc=current_setting('kmb.renegociacao_autorizada',true);perform set_config('kmb.renegociacao_autorizada','sim',true);
  update public.kmb_vendas set valor_total=valor_total+fee where id=sale;
  perform set_config('kmb.renegociacao_autorizada',coalesce(old_guc,''),true);
  insert into public.kmb_parcelas(venda_id,numero,valor,data_vencimento,criado_por) values(sale,2,fee,(now() at time zone 'America/Sao_Paulo')::date,auth.uid());
 end if;
 update public.kmuv2_orders set status='accepted',sale_id=sale,shipping=fee,subtotal=v_subtotal,verified_contact=true,decided_at=now(),decided_by=auth.uid() where id=p_id;
 return jsonb_build_object('status','accepted','sale_id',sale,'total',v_subtotal+fee,'payment_confirmed',false);end $$;