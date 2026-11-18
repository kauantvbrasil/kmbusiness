create function kmuv2_private.classic_edit(p_key uuid,p_id uuid,p_version bigint,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare v public.kmb_vendas%rowtype;previous kmuv2_private.business_commands%rowtype;h text;result jsonb;cid uuid;item jsonb;plans jsonb;received numeric;plan_received numeric;total numeric;meta jsonb;begin
 perform kmuv2_private.authorize_admin();if not kmuv2_private.current_sale(p_id) then raise exception 'O registro anterior é preservado para consulta.';end if;
 h=md5(jsonb_build_object('id',p_id,'version',p_version,'data',p)::text);perform pg_advisory_xact_lock(hashtextextended(p_key::text,5));select * into previous from kmuv2_private.business_commands where id=p_key;
 if found then if previous.hash<>h then raise exception 'Operação já usada com outros dados.';end if;return previous.result;end if;
 select * into v from public.kmb_vendas where id=p_id for update;if v.versao_edicao is distinct from p_version then raise exception 'A venda mudou. Reabra e confira antes de salvar.' using errcode='40001';end if;
 if jsonb_array_length(p->'items')<>1 then raise exception 'Confira os itens da venda.';end if;
 for item in select value from jsonb_array_elements(p->'items') loop
  perform 1 from public.kmuv2_models where product_id=(item->>'id')::uuid for update;if not found then raise exception 'Modelo fora da operação atual.';end if;
 end loop;
 if exists(select 1 from public.kmb_venda_itens i where i.venda_id=p_id and i.produto_id is null) or (select count(*) from public.kmb_venda_itens where venda_id=p_id)<>1 then raise exception 'Esta venda possui vários itens. Preserve os itens e revise pelo pedido de origem.';end if;
 select coalesce(sum(valor),0) into received from public.kmb_pagamentos where venda_id=p_id;
 select sum((value->>'v')::numeric),coalesce(sum((value->>'v')::numeric) filter(where (value->>'paid')::boolean),0),coalesce(jsonb_agg(jsonb_build_object('valor',(value->>'v')::numeric,'vencimento',value->>'d')) filter(where not (value->>'paid')::boolean),'[]') into total,plan_received,plans from jsonb_array_elements(p->'plan');
 if total is distinct from (p->>'price')::numeric or received is distinct from plan_received then raise exception 'Mantenha os recebimentos conferidos e confira a soma das parcelas. Use Registrar recebimento para novos pagamentos.';end if;
 item=p->'items'->0;
 perform public.kmb_editar_itens_venda(p_id,p_version,jsonb_build_array(jsonb_build_object('produto_id',(item->>'id')::uuid,'quantidade',1,'preco_unitario',(p->>'price')::numeric+v.desconto_valor,'custo_unitario',(p->>'cost')::numeric)),'Edição revisada no Business');
 result=kmuv2_private.business_command(md5('classic-edit-client:'||p_key::text)::uuid,'client',jsonb_build_object('name',p->>'clientName','phone',p->>'phone','notes','Cadastro revisado pelo Business'));cid=(result->>'id')::uuid;
 select * into v from public.kmb_vendas where id=p_id;
 perform public.kmb_editar_identificacao_venda(p_id,v.versao_edicao,cid,(p->>'date')::date,p->>'notes','Identificação revisada no Business');
 perform public.kmb_renegociar_venda_v2(p_id,(p->>'price')::numeric,'Planejamento revisado no Business',plans);
 update public.kmuv2_models set revision=revision+1 where product_id in (select (value->>'id')::uuid from jsonb_array_elements(p->'items'));
 meta=jsonb_build_object('id','sale_meta_'||p_id,'kind','sale_metadata','owner',left(coalesce(p->>'owner',''),100),'paymentMethod',left(coalesce(p->>'paymentMethod',''),50),'fees',coalesce((p->>'fees')::numeric,0),'saleExpenses',coalesce((p->>'saleExpenses')::numeric,0));
 if (meta->>'fees')::numeric<0 or (meta->>'saleExpenses')::numeric<0 then raise exception 'Confira taxas e despesas.';end if;
 insert into kmuv2_private.classic_records(collection,id,data) values('config',meta->>'id',meta) on conflict(collection,id) do update set data=excluded.data,updated_at=now();
 result=jsonb_build_object('venda_id',p_id,'sucesso',true);insert into kmuv2_private.business_commands(id,hash,result) values(p_key,h,result);return result;
end$$;
create function public.kmuv2_classic_edit(p_key uuid,p_id uuid,p_version bigint,p jsonb) returns jsonb language sql security invoker set search_path='' as $$select kmuv2_private.classic_edit(p_key,p_id,p_version,p)$$;
revoke all on function kmuv2_private.classic_edit(uuid,uuid,bigint,jsonb),public.kmuv2_classic_edit(uuid,uuid,bigint,jsonb) from public,anon,authenticated,service_role;
grant execute on function kmuv2_private.classic_edit(uuid,uuid,bigint,jsonb),public.kmuv2_classic_edit(uuid,uuid,bigint,jsonb) to authenticated;
