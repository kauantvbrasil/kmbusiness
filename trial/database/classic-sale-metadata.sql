create or replace function kmuv2_private.classic_sale(p_key uuid,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
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
