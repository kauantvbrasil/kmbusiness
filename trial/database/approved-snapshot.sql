alter table public.kmuv2_orders add column approved_items jsonb;
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
  if not product.ativo or product.estoque_atual<row.quantity then raise exception 'Estoque insuficiente. Nenhuma venda foi registrada.';end if;
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