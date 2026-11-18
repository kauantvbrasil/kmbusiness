-- Original Business UI adapter. Metadata is private; financial history remains immutable.
create table kmuv2_private.classic_records(collection text not null check(collection in ('config','closings','proofs')),id text not null,data jsonb not null,updated_at timestamptz not null default now(),primary key(collection,id));
alter table kmuv2_private.classic_records enable row level security;
revoke all on kmuv2_private.classic_records from public,anon,authenticated;
create function kmuv2_private.classic_metadata() returns jsonb language plpgsql security definer set search_path='' as $$begin perform kmuv2_private.authorize_admin();return coalesce((select jsonb_agg(jsonb_build_object('collection',collection,'data',data)) from kmuv2_private.classic_records),'[]');end$$;
create function public.kmuv2_classic_metadata() returns jsonb language sql security invoker set search_path='' as $$select kmuv2_private.classic_metadata()$$;
create function kmuv2_private.classic_write(p_collection text,p_data jsonb,p_expected text) returns jsonb language plpgsql security definer set search_path='' as $$
declare previous jsonb;rid text;result jsonb;begin
 perform kmuv2_private.authorize_admin();rid=p_data->>'id';
 if p_collection not in ('config','closings','proofs') or length(coalesce(rid,'')) not between 1 and 150 or jsonb_typeof(p_data) is distinct from 'object' or octet_length(p_data::text)>5000000 then raise exception 'Registro inválido.';end if;
 perform pg_advisory_xact_lock(hashtextextended(p_collection||rid,3));select data into previous from kmuv2_private.classic_records where collection=p_collection and id=rid for update;
 if found and coalesce(previous->>'updatedAt','')<>coalesce(p_expected,'') then raise exception 'Outra pessoa atualizou este registro. Atualize a tela e confira.' using errcode='40001';end if;
 result=p_data||jsonb_build_object('updatedAt',now());
 insert into kmuv2_private.classic_records(collection,id,data) values(p_collection,rid,result) on conflict(collection,id) do update set data=excluded.data,updated_at=now();return result;
end$$;
create function public.kmuv2_classic_write(p_collection text,p_data jsonb,p_expected text default '') returns jsonb language sql security invoker set search_path='' as $$select kmuv2_private.classic_write(p_collection,p_data,p_expected)$$;

create function kmuv2_private.classic_stock(p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare k uuid;h text;prev kmuv2_private.business_commands%rowtype;item jsonb;prod public.kmb_produtos%rowtype;items jsonb='[]';qty integer;rec jsonb;begin
 perform kmuv2_private.authorize_admin();
 if length(coalesce(p->>'id','')) not between 1 and 150 or p->>'kind' not in ('inbound','count') or length(btrim(coalesce(p->>'reason',''))) not between 3 and 500 or jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') not between 1 and 100 then raise exception 'Confira a movimentação.';end if;
 k=md5('classic-stock:'||(p->>'id'))::uuid;h=md5(p::text);perform pg_advisory_xact_lock(hashtextextended(k::text,1));select * into prev from kmuv2_private.business_commands where id=k;
 if found then if prev.hash<>h then raise exception 'Operação já usada com outros dados.';end if;return prev.result;end if;
 if (select count(*)<>count(distinct value->>'pid') from jsonb_array_elements(p->'items')) then raise exception 'Use uma linha por modelo.';end if;
 for item in select value from jsonb_array_elements(p->'items') order by value->>'pid' loop
  perform 1 from public.kmuv2_models where product_id=(item->>'pid')::uuid for update;if not found then raise exception 'Modelo fora da operação atual.';end if;
  select * into prod from public.kmb_produtos where id=(item->>'pid')::uuid for update;
  if (item->>'qty')::integer not between 0 and 100000 or nullif(item->>'qty','') is null then raise exception 'Quantidade inválida.';end if;
  if p->>'kind'='count' and prod.estoque_atual is distinct from (item->>'expected')::integer then raise exception 'O estoque mudou. Reabra a conferência.' using errcode='40001';end if;
  qty=public.kmb_movimentar_estoque(prod.id,case when p->>'kind'='count' then 'ajuste' else 'entrada' end,(item->>'qty')::integer,p->>'reason');
  if p->>'kind'='inbound' then
   if nullif(item->>'cost','') is null or (item->>'cost')::numeric<0 or round((item->>'cost')::numeric,2)<>(item->>'cost')::numeric then raise exception 'Custo inválido.';end if;
   update public.kmb_produtos set preco_custo=(item->>'cost')::numeric,atualizado_em=now() where id=prod.id;
  end if;
  update public.kmuv2_models set revision=revision+1 where product_id=prod.id;
  items=items||jsonb_build_object('pid',prod.id,'name',prod.nome,'before',prod.estoque_atual,'after',qty,'delta',qty-prod.estoque_atual,'cost',coalesce((item->>'cost')::numeric,prod.preco_custo));
 end loop;
 rec=jsonb_build_object('id',p->>'id','type','b3-stock-operation','kind',p->>'kind','reason',p->>'reason','actor','Administrador','at',now(),'items',items);
 insert into kmuv2_private.classic_records(collection,id,data) values('config',p->>'id',rec);
 insert into kmuv2_private.business_commands(id,hash,result) values(k,h,rec);return rec;
end$$;
create function public.kmuv2_classic_stock(p jsonb) returns jsonb language sql security invoker set search_path='' as $$select kmuv2_private.classic_stock(p)$$;

create function kmuv2_private.classic_sale(p_key uuid,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare h text;prev kmuv2_private.business_commands%rowtype;result jsonb;cid uuid;sid uuid;plans jsonb;total numeric;paid numeric;key_sale uuid;meta jsonb;begin
 perform kmuv2_private.authorize_admin();h=md5(p::text);perform pg_advisory_xact_lock(hashtextextended(p_key::text,4));select * into prev from kmuv2_private.business_commands where id=p_key;
 if found then if prev.hash<>h then raise exception 'Operação já usada com outros dados.';end if;return prev.result;end if;
 -- Check the scope explicitly before creating a client or invoking financial routines.
 if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') not between 1 and 30 then raise exception 'Selecione modelos da operação atual.';end if;
 if exists(select 1 from jsonb_array_elements(p->'items') x left join public.kmuv2_models m on m.product_id=(x->>'id')::uuid and m.operation_kind='apparel' where m.product_id is null) then raise exception 'Um dos modelos não pertence à operação atual.';end if;
 -- A nested key isolates this atomic orchestration from the existing sale command.
 key_sale=md5('classic-sale:'||p_key::text)::uuid;
 result=kmuv2_private.business_command(md5('classic-client:'||p_key::text)::uuid,'client',jsonb_build_object('name',p->>'clientName','phone',p->>'phone','notes','Cadastro pelo Business'));
 cid=(result->>'id')::uuid;
 if jsonb_typeof(p->'plan') is distinct from 'array' or jsonb_array_length(p->'plan') not between 1 and 37 then raise exception 'Confira o parcelamento.';end if;
 select sum((value->>'v')::numeric),coalesce(sum((value->>'v')::numeric) filter(where (value->>'paid')::boolean),0),coalesce(jsonb_agg(jsonb_build_object('valor',(value->>'v')::numeric,'vencimento',value->>'d')) filter(where not (value->>'paid')::boolean),'[]') into total,paid,plans from jsonb_array_elements(p->'plan');
 if total is distinct from (p->>'price')::numeric then raise exception 'As parcelas precisam somar o valor da venda.';end if;
 result=kmuv2_private.business_command(key_sale,'sale',jsonb_build_object('client',cid,'date',p->>'date','discount',p->'discount','entry',paid,'paymentConfirmed',p->'paymentConfirmed','due',p->'due','method',p->>'method','notes',p->>'notes','items',p->'items'));
 sid=(result->>'venda_id')::uuid;
 if (select valor_total from public.kmb_vendas where id=sid) is distinct from total then raise exception 'O valor mudou. Confira a venda.';end if;
 if jsonb_array_length(plans)>1 then perform public.kmb_renegociar_venda_v2(sid,total,'Parcelamento revisado no cadastro',plans);end if;
 meta=jsonb_build_object('id','sale_meta_'||sid,'kind','sale_metadata','owner',left(coalesce(p->>'owner',''),100),'paymentMethod',left(coalesce(p->>'paymentMethod',''),50),'fees',coalesce((p->>'fees')::numeric,0),'saleExpenses',coalesce((p->>'saleExpenses')::numeric,0));
 if (meta->>'fees')::numeric<0 or (meta->>'saleExpenses')::numeric<0 then raise exception 'Confira taxas e despesas.';end if;
 insert into kmuv2_private.classic_records(collection,id,data) values('config',meta->>'id',meta);
 insert into kmuv2_private.business_commands(id,hash,result) values(p_key,h,result);return result;
end$$;
create function public.kmuv2_classic_sale(p_key uuid,p jsonb) returns jsonb language sql security invoker set search_path='' as $$select kmuv2_private.classic_sale(p_key,p)$$;

revoke all on function kmuv2_private.classic_metadata(),kmuv2_private.classic_write(text,jsonb,text),kmuv2_private.classic_stock(jsonb),kmuv2_private.classic_sale(uuid,jsonb),public.kmuv2_classic_metadata(),public.kmuv2_classic_write(text,jsonb,text),public.kmuv2_classic_stock(jsonb),public.kmuv2_classic_sale(uuid,jsonb) from public,anon,authenticated,service_role;
grant execute on function kmuv2_private.classic_metadata(),kmuv2_private.classic_write(text,jsonb,text),kmuv2_private.classic_stock(jsonb),kmuv2_private.classic_sale(uuid,jsonb),public.kmuv2_classic_metadata(),public.kmuv2_classic_write(text,jsonb,text),public.kmuv2_classic_stock(jsonb),public.kmuv2_classic_sale(uuid,jsonb) to authenticated;
