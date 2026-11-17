-- Additional administration modules; existing financial routines remain authoritative.
create table kmuv2_private.business_records(kind text not null check(kind in ('client','expense','sale')),record_id uuid not null,created_at timestamptz not null default now(),primary key(kind,record_id));
create table kmuv2_private.business_documents(id uuid primary key default gen_random_uuid(),kind text not null check(kind in ('task','archive')),data jsonb not null,source_text text,revision bigint not null default 1,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),actor uuid references auth.users);
create unique index kmuv2_archive_digest on kmuv2_private.business_documents((data->>'checksum')) where kind='archive';
create table kmuv2_private.business_commands(id uuid primary key,hash text not null,result jsonb not null,created_at timestamptz not null default now());
alter table kmuv2_private.business_records enable row level security;
alter table kmuv2_private.business_documents enable row level security;
alter table kmuv2_private.business_commands enable row level security;
revoke all on kmuv2_private.business_records,kmuv2_private.business_documents,kmuv2_private.business_commands from public,anon,authenticated;

create function kmuv2_private.current_sale(p_id uuid) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.kmuv2_orders where sale_id=p_id) or exists(select 1 from kmuv2_private.business_records where kind='sale' and record_id=p_id)
$$;
revoke all on function kmuv2_private.current_sale(uuid) from public,anon,authenticated;

create function kmuv2_private.business_data() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 perform kmuv2_private.authorize_admin();
 return jsonb_build_object(
 'clients',(select coalesce(jsonb_agg(to_jsonb(c) order by c.nome),'[]') from public.kmb_clientes c where exists(select 1 from kmuv2_private.business_records r where r.kind='client' and r.record_id=c.id) or exists(select 1 from public.kmb_vendas s where s.cliente_id=c.id and kmuv2_private.current_sale(s.id))),
 'expenses',(select coalesce(jsonb_agg(to_jsonb(e) order by e.data_despesa desc),'[]') from public.kmb_despesas e join kmuv2_private.business_records r on r.kind='expense' and r.record_id=e.id),
 'items',(select coalesce(jsonb_agg(to_jsonb(i)),'[]') from public.kmb_venda_itens i where kmuv2_private.current_sale(i.venda_id)),
 'payments',(select coalesce(jsonb_agg(to_jsonb(p) order by p.data_pagamento desc,p.criado_em desc),'[]') from public.kmb_pagamentos p where kmuv2_private.current_sale(p.venda_id)),
 'sales',(select coalesce(jsonb_agg(to_jsonb(v) order by v.data_venda desc,v.criado_em desc),'[]') from public.kmb_vendas v where kmuv2_private.current_sale(v.id)),
 'installments',(select coalesce(jsonb_agg(to_jsonb(p) order by p.data_vencimento),'[]') from public.kmb_parcelas p where kmuv2_private.current_sale(p.venda_id)),
 'movements',(select coalesce(jsonb_agg(to_jsonb(x) order by x.criado_em desc),'[]') from public.kmb_estoque_movimentacoes x join public.kmuv2_models m on m.product_id=x.produto_id),
 'tasks',(select coalesce(jsonb_agg(to_jsonb(d) order by d.data->>'date'),'[]') from kmuv2_private.business_documents d where d.kind='task'),
 'archives',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'created_at',created_at,'sourceDate',data->>'createdAt','checksum',data->>'checksum','counts',jsonb_build_object('sales',jsonb_array_length(data->'data'->'sales'),'products',jsonb_array_length(data->'data'->'products'),'expenses',jsonb_array_length(data->'data'->'expenses')))),'[]') from kmuv2_private.business_documents where kind='archive'));
end $$;
create function public.kmuv2_business_data() returns jsonb language sql security invoker set search_path='' as $$select kmuv2_private.business_data()$$;

create function kmuv2_private.business_command(p_key uuid,p_action text,p jsonb) returns jsonb language plpgsql security definer set search_path='' as $$
declare saved kmuv2_private.business_commands%rowtype;h text;out jsonb;rid uuid;row record;prod public.kmb_produtos%rowtype;items jsonb='[]';rev bigint;amount numeric;actual integer;current_day date=(now() at time zone 'America/Sao_Paulo')::date;
begin
 perform kmuv2_private.authorize_admin();
 if p_key is null or p is null then raise exception 'Operação inválida.';end if;
 h=md5(p_action||p::text);perform pg_advisory_xact_lock(hashtextextended(p_key::text,1));select * into saved from kmuv2_private.business_commands where id=p_key;
 if found then if saved.hash<>h then raise exception 'Chave já utilizada em outra operação.';end if;return saved.result;end if;
 if p_action='client' then
  if length(btrim(coalesce(p->>'name',''))) not between 2 and 120 or length(coalesce(p->>'phone',''))>20 or length(coalesce(p->>'notes',''))>1000 then raise exception 'Confira nome, contato e observações.';end if;
  if nullif(p->>'id','') is not null then
   rid=(p->>'id')::uuid;
   if not exists(select 1 from kmuv2_private.business_records where kind='client' and record_id=rid) then raise exception 'Ficha histórica disponível somente para consulta.';end if;
   perform 1 from public.kmb_clientes where id=rid and atualizado_em=(p->>'updated_at')::timestamptz for update;if not found then raise exception 'Ficha alterada. Atualize antes de editar.';end if;
   update public.kmb_clientes set nome=btrim(p->>'name'),telefone=p->>'phone',observacoes=p->>'notes',atualizado_em=now() where id=rid;
  else
   insert into public.kmb_clientes(nome,telefone,observacoes) values(btrim(p->>'name'),p->>'phone',p->>'notes') returning id into rid;
   insert into kmuv2_private.business_records values('client',rid,now());
  end if;out=jsonb_build_object('id',rid);
 elsif p_action='expense' then
  amount=(p->>'amount')::numeric;
  if length(btrim(coalesce(p->>'description',''))) not between 3 and 200 or amount is null or amount<=0 or amount>99999999 or round(amount,2)<>amount or (p->>'date')::date>current_day or nullif(p->>'date','') is null then raise exception 'Confira os dados da despesa.';end if;
  insert into public.kmb_despesas(descricao,categoria,valor,data_despesa,observacoes,criado_por) values(btrim(p->>'description'),'outros',amount,(p->>'date')::date,left(coalesce(p->>'notes',''),1000),auth.uid()) returning id into rid;
  insert into kmuv2_private.business_records values('expense',rid,now());out=jsonb_build_object('id',rid);
 elsif p_action='sale' then
  if jsonb_typeof(p->'items') is distinct from 'array' or jsonb_array_length(p->'items') not between 1 and 30 then raise exception 'Selecione de 1 a 30 modelos.';end if;
  if (p->>'date')::date>current_day then raise exception 'A data da venda não pode ser futura.';end if;
  for row in select * from jsonb_to_recordset(p->'items') as x(id uuid,quantity integer,price numeric,revision bigint) order by id loop
   perform 1 from public.kmuv2_models where product_id=row.id and operation_kind='apparel' and revision=row.revision for update;
   if not found then raise exception 'Modelo alterado ou fora da operação atual. Confira novamente.';end if;
   select * into prod from public.kmb_produtos where id=row.id for update;
   if prod.arquivado or not prod.ativo or prod.preco_venda is distinct from row.price then raise exception 'Disponibilidade ou preço alterado. Confira novamente.';end if;
   items=items||jsonb_build_object('produto_id',row.id,'quantidade',row.quantity);
  end loop;
  if nullif(p->>'client','') is null then raise exception 'Selecione o cliente.';end if;
  if not exists(select 1 from kmuv2_private.business_records where kind='client' and record_id=(p->>'client')::uuid) then raise exception 'Cadastre uma ficha do cliente para esta operação.';end if;
  if coalesce((p->>'entry')::numeric,0)>0 and coalesce((p->>'paymentConfirmed')::boolean,false) is not true then raise exception 'Confirme o recebimento da entrada.';end if;
  out=public.kmb_confirmar_venda_expressa(p_chave_operacao=>p_key,p_itens=>items,p_cliente_id=>(p->>'client')::uuid,p_data_venda=>(p->>'date')::date,p_desconto=>(p->>'discount')::numeric,p_entrada=>(p->>'entry')::numeric,p_forma_pagamento=>case when (p->>'entry')::numeric>0 then p->>'method' else null end,p_vencimento=>(p->>'due')::date,p_observacoes=>left(coalesce(p->>'notes',''),1000));
  rid=(out->>'venda_id')::uuid;insert into kmuv2_private.business_records values('sale',rid,now()) on conflict do nothing;
  update public.kmuv2_models set revision=revision+1 where product_id in(select (value->>'id')::uuid from jsonb_array_elements(p->'items'));
 elsif p_action='payment' then
  select venda_id into rid from public.kmb_parcelas where id=(p->>'installment')::uuid;
  if not kmuv2_private.current_sale(rid) then raise exception 'Parcela fora da operação atual.';end if;
  if (p->>'confirmed')::boolean is distinct from true or (p->>'date')::date>current_day then raise exception 'Confira o recebimento e a data.';end if;
  out=public.kmb_receber_parcela((p->>'installment')::uuid,(p->>'amount')::numeric,p->>'method',(p->>'date')::date);
 elsif p_action='stock' then
  select revision into rev from public.kmuv2_models where product_id=(p->>'id')::uuid for update;
  if rev is null or rev is distinct from (p->>'revision')::bigint then raise exception 'Estoque alterado. Atualize e confira.';end if;
  if p->>'mode' not in ('entrada','ajuste') or (p->>'quantity')::integer not between 0 and 100000 then raise exception 'Movimentação inválida.';end if;
  actual=public.kmb_movimentar_estoque((p->>'id')::uuid,p->>'mode',(p->>'quantity')::integer,p->>'reason');
  update public.kmuv2_models set revision=revision+1 where product_id=(p->>'id')::uuid;out=jsonb_build_object('stock',actual);
 elsif p_action='task' then
  if length(btrim(coalesce(p->>'title',''))) not between 2 and 150 or nullif(p->>'date','') is null then raise exception 'Informe título e data.';end if;
  perform (p->>'date')::date;
  if nullif(p->>'id','') is null then
   insert into kmuv2_private.business_documents(kind,data,actor) values('task',jsonb_build_object('title',p->>'title','date',p->>'date','notes',left(coalesce(p->>'notes',''),1000),'done',false),auth.uid()) returning id into rid;
  else
   rid=(p->>'id')::uuid;
   update kmuv2_private.business_documents set data=jsonb_build_object('title',p->>'title','date',p->>'date','notes',left(coalesce(p->>'notes',''),1000),'done',coalesce((p->>'done')::boolean,false)),revision=revision+1,updated_at=now(),actor=auth.uid() where id=rid and kind='task' and revision=(p->>'revision')::bigint;
   if not found then raise exception 'Tarefa alterada. Confira a versão atual.';end if;
  end if;out=jsonb_build_object('id',rid);
 else raise exception 'Operação desconhecida.';end if;
 insert into kmuv2_private.business_commands(id,hash,result) values(p_key,h,out);return out;
end $$;
create function public.kmuv2_business_command(p_key uuid,p_action text,p jsonb) returns jsonb language sql security invoker set search_path='' as $$select kmuv2_private.business_command(p_key,p_action,p)$$;

create function kmuv2_private.archive_backup(p_raw text) returns uuid language plpgsql security definer set search_path='' as $$
declare rid uuid;k text;p jsonb;begin
 perform kmuv2_private.authorize_admin();
 if octet_length(p_raw)>20000000 then raise exception 'Backup muito grande.';end if;
 p=p_raw::jsonb;
 if p->>'format' is distinct from 'km-business-backup' or p->>'version' is distinct from '1' or p->>'algorithm' is distinct from 'SHA-256' or p->>'checksum' !~ '^[a-f0-9]{64}$' or jsonb_typeof(p->'data') is distinct from 'object' or octet_length(p::text)>20000000 then raise exception 'Backup histórico inválido.';end if;
 foreach k in array array['products','sales','expenses','closings','config','proofs','catalog','cphotos'] loop
  if jsonb_typeof(p->'data'->k) is distinct from 'array' then raise exception 'O backup está incompleto.';end if;
 end loop;
 select id into rid from kmuv2_private.business_documents where kind='archive' and data->>'checksum'=p->>'checksum';
 if rid is not null then return rid;end if;
 insert into kmuv2_private.business_documents(kind,data,source_text,actor) values('archive',p,p_raw,auth.uid()) on conflict do nothing returning id into rid;
 if rid is null then select id into rid from kmuv2_private.business_documents where kind='archive' and data->>'checksum'=p->>'checksum';end if;return rid;
end $$;
create function public.kmuv2_archive_backup(p_raw text) returns uuid language sql security invoker set search_path='' as $$select kmuv2_private.archive_backup(p_raw)$$;
create function kmuv2_private.read_archive(p_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare out jsonb;begin perform kmuv2_private.authorize_admin();select jsonb_build_object('envelope',data,'sourceText',source_text) into out from kmuv2_private.business_documents where id=p_id and kind='archive';return out;end$$;
create function public.kmuv2_read_archive(p_id uuid) returns jsonb language sql security invoker set search_path='' as $$select kmuv2_private.read_archive(p_id)$$;

revoke all on function kmuv2_private.business_data(),kmuv2_private.business_command(uuid,text,jsonb),kmuv2_private.archive_backup(text),kmuv2_private.read_archive(uuid),public.kmuv2_business_data(),public.kmuv2_business_command(uuid,text,jsonb),public.kmuv2_archive_backup(text),public.kmuv2_read_archive(uuid) from public,anon,authenticated,service_role;
grant execute on function kmuv2_private.business_data(),kmuv2_private.business_command(uuid,text,jsonb),kmuv2_private.archive_backup(text),kmuv2_private.read_archive(uuid),public.kmuv2_business_data(),public.kmuv2_business_command(uuid,text,jsonb),public.kmuv2_archive_backup(text),public.kmuv2_read_archive(uuid) to authenticated;
