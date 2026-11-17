create or replace function kmuv2_private.catalog() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;begin perform kmuv2_private.authorize_service();
 select jsonb_build_object('products',coalesce(jsonb_agg(jsonb_build_object('id',p.id,'brand',p.marca,'model',p.modelo,'size',p.variacao,'price',p.preco_venda,'photo',p.foto_url,'description',p.descricao,'available',p.ativo and not p.arquivado and p.estoque_atual>0,'stock',p.estoque_atual) order by m.sort_order,p.criado_em) filter(where m.visible and not p.arquivado),'[]'::jsonb),'collections',jsonb_build_object('bestSellers',coalesce(jsonb_agg(p.id) filter(where m.visible and not p.arquivado and 'bestSellers'=any(m.collections)),'[]'::jsonb),'budget',coalesce(jsonb_agg(p.id) filter(where m.visible and not p.arquivado and 'budget'=any(m.collections)),'[]'::jsonb),'newArrivals',coalesce(jsonb_agg(p.id) filter(where m.visible and not p.arquivado and 'newArrivals'=any(m.collections)),'[]'::jsonb))) into result from public.kmuv2_models m join public.kmb_produtos p on p.id=m.product_id where m.operation_kind='apparel';
 return result||(select data from public.kmuv2_settings where id=true);end $$;
create or replace function kmuv2_private.save_model(p jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare pid uuid; revision_now bigint; old_stock integer; key text;begin
 perform kmuv2_private.authorize_admin();
 if coalesce(p->>'price','') !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' or coalesce(p->>'cost','') !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' or coalesce(p->>'stock','') !~ '^[0-9]{1,6}$' or p->>'kind' is distinct from 'apparel' or length(btrim(p->>'brand')) not between 1 and 80 or length(btrim(p->>'model')) not between 1 and 100 or length(btrim(p->>'size')) not between 1 and 60 or (p->>'price')::numeric<=0 or round((p->>'price')::numeric,2)<>(p->>'price')::numeric or (p->>'cost')::numeric<0 or (p->>'stock')::integer not between 0 and 100000 then raise exception 'Confira os dados do modelo.';end if;
 if lower(concat_ws(' ',p->>'brand',p->>'model')) ~ '(elfbar|elf bar|ignite|dinner lady|puffs|vape|nicotin)' then raise exception 'Este registro não pertence à operação atual.';end if;
 if p->>'photo' not like 'https://xzcwmhrdfueutareqxjw.supabase.co/storage/v1/object/public/kmuv2-photos/%' then raise exception 'Envie uma foto válida.';end if;
 if exists(select 1 from jsonb_array_elements_text(coalesce(p->'collections','[]'))x where x not in ('bestSellers','budget','newArrivals')) then raise exception 'Seleção inválida.';end if;
 key=lower(btrim(p->>'brand'))||'|'||lower(btrim(p->>'model'))||'|'||lower(btrim(p->>'size'));
 if nullif(p->>'id','') is null then
  if exists(select 1 from public.kmuv2_models where canonical_key=key) then raise exception 'Este modelo já está cadastrado.';end if;
  pid=public.kmb_criar_produto(p_nome=>btrim(p->>'model'),p_preco_venda=>(p->>'price')::numeric,p_preco_custo=>(p->>'cost')::numeric,p_estoque_inicial=>(p->>'stock')::integer);
  insert into public.kmuv2_models(product_id,canonical_key,visible,collections) values(pid,key,coalesce((p->>'visible')::boolean,true),array(select jsonb_array_elements_text(coalesce(p->'collections','["newArrivals"]'))));
 else
  pid=(p->>'id')::uuid;select revision into revision_now from public.kmuv2_models where product_id=pid for update;
  if not found then raise exception 'Registro histórico não pode entrar nesta operação.';end if;
  if (p->>'revision')::bigint is distinct from revision_now then raise exception 'O modelo mudou. Atualize antes de salvar.' using errcode='40001';end if;
  select estoque_atual into old_stock from public.kmb_produtos where id=pid for update;
  insert into kmuv2_private.snapshots(actor,data) select auth.uid(),jsonb_build_object('product',to_jsonb(t),'metadata',to_jsonb(m)) from public.kmb_produtos t join public.kmuv2_models m on m.product_id=t.id where t.id=pid;
  update public.kmuv2_models set canonical_key=key,collections=array(select jsonb_array_elements_text(coalesce(p->'collections','[]'))),visible=coalesce((p->>'visible')::boolean,true),revision=revision+1 where product_id=pid;
  if old_stock<>(p->>'stock')::integer then
   update public.kmb_produtos set estoque_atual=(p->>'stock')::integer where id=pid;
   insert into public.kmb_estoque_movimentacoes(produto_id,tipo,quantidade,motivo,registrado_por) values(pid,'ajuste',(p->>'stock')::integer-old_stock,'Ajuste conferido no painel',auth.uid());
  end if;
 end if;
 update public.kmb_produtos set marca=btrim(p->>'brand'),modelo=btrim(p->>'model'),variacao=btrim(p->>'size'),nome=btrim(p->>'model'),preco_venda=(p->>'price')::numeric,preco_custo=(p->>'cost')::numeric,descricao=left(coalesce(p->>'description',''),1000),foto_url=p->>'photo',ativo=coalesce((p->>'active')::boolean,true),atualizado_em=now() where id=pid;
 return pid;end $$;
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
  if not found or not product.ativo or product.arquivado or product.estoque_atual<item.quantity then raise exception 'Um modelo ficou indisponível. Revise a sacola.';end if;
  if (item.brand is not null and item.brand is distinct from product.marca) or (item.model is not null and item.model is distinct from product.modelo) or (item.size is not null and item.size is distinct from product.variacao) then raise exception 'Os detalhes mudaram. Atualize e revise a sacola.';end if;
  if item.price is distinct from product.preco_venda then raise exception 'Um valor mudou. Atualize e revise a sacola.';end if;
  total=total+product.preco_venda*item.quantity;
  rows=rows||jsonb_build_object('id',product.id,'brand',product.marca,'model',product.modelo,'size',product.variacao,'quantity',item.quantity,'price',product.preco_venda,'photo',product.foto_url);
 end loop;
 if p->>'mode'='delivery' and (jsonb_typeof(p->'address') is distinct from 'object' or length(p#>>'{address,cep}')<>8 or length(p#>>'{address,street}')<2 or length(p#>>'{address,number}')<1 or length(p#>>'{address,reference}')<1) then raise exception 'Endereço incompleto.';end if;
 insert into public.kmuv2_orders(idempotency_key,request_hash,customer_name,items,subtotal,mode,address,shipping,notes) values((p->>'key')::uuid,hash,btrim(p->>'name'),rows,total,p->>'mode',case when p->>'mode'='delivery' then p->'address' else null end,case when p->>'mode'='pickup' then 0 else (p->>'shipping')::numeric end,coalesce(p->>'notes','')) returning * into existing;
 return jsonb_build_object('id',existing.id,'code',existing.code,'subtotal',existing.subtotal,'shipping',existing.shipping,'status','pending','verified',false);end $$;
create or replace function kmuv2_private.decide_order(p_id uuid,p_accept boolean,p_prices jsonb,p_shipping numeric,p_reason text,p_contact boolean) returns jsonb language plpgsql security definer set search_path='' as $$
declare o public.kmuv2_orders%rowtype; row record; product public.kmb_produtos%rowtype; rows jsonb='[]'; approved_rows jsonb='[]'; customer uuid; result jsonb; sale uuid; v_subtotal numeric=0; fee numeric; old_guc text;begin
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
  if not product.ativo or product.arquivado or product.estoque_atual<row.quantity then raise exception 'Estoque insuficiente. Nenhuma venda foi registrada.';end if;
  if row.brand is distinct from product.marca or row.model is distinct from product.modelo or row.size is distinct from product.variacao then raise exception 'Os detalhes do modelo mudaram. Peça uma nova revisão ao cliente.' using errcode='40001';end if;
  if (p_prices->>row.id::text)::numeric is distinct from product.preco_venda then raise exception 'Os valores mudaram. Reabra e confira a solicitação.' using errcode='40001';end if;
  approved_rows=approved_rows||jsonb_build_object('id',product.id,'brand',product.marca,'model',product.modelo,'size',product.variacao,'quantity',row.quantity,'price',product.preco_venda,'photo',product.foto_url);rows=rows||jsonb_build_object('produto_id',row.id,'quantidade',row.quantity);v_subtotal=v_subtotal+row.quantity*product.preco_venda;
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
 update public.kmuv2_orders set status='accepted',approved_items=approved_rows,sale_id=sale,shipping=fee,subtotal=v_subtotal,verified_contact=true,decided_at=now(),decided_by=auth.uid() where id=p_id;
 return jsonb_build_object('status','accepted','sale_id',sale,'total',v_subtotal+fee,'payment_confirmed',false);end $$;