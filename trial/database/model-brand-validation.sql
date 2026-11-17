-- Brand/model names are not a reliable product classification.
-- Historical IDs remain excluded from all current-operation writes.
create or replace function kmuv2_private.save_model(p jsonb) returns uuid language plpgsql security definer set search_path='' as $$
declare pid uuid; revision_now bigint; old_stock integer; key text;begin
 perform kmuv2_private.authorize_admin();
 if coalesce(p->>'price','') !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' or coalesce(p->>'cost','') !~ '^[0-9]{1,8}(\.[0-9]{1,2})?$' or coalesce(p->>'stock','') !~ '^[0-9]{1,6}$' or p->>'kind' is distinct from 'apparel' or length(btrim(p->>'brand')) not between 1 and 80 or length(btrim(p->>'model')) not between 1 and 100 or length(btrim(p->>'size')) not between 1 and 60 or (p->>'price')::numeric<=0 or round((p->>'price')::numeric,2)<>(p->>'price')::numeric or (p->>'cost')::numeric<0 or (p->>'stock')::integer not between 0 and 100000 then raise exception 'Confira os dados do modelo.';end if;
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
