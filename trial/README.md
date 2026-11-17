# Versão separada da central e do catálogo

Endereços:
- Central: https://kmimportsz.github.io/kmbusiness/trial/
- Catálogo: https://kmimportsz.github.io/kmbusiness/trial/catalogo/

Os arquivos existentes fora de `trial/` não são alterados. Não existe importação automática do Firebase, R2 ou de produtos históricos do Supabase. O cadastro começa vazio. As preferências, a sacola e a sessão desta versão usam chaves locais diferentes das anteriores.

## Fonte oficial

Reutiliza o projeto Supabase ativo existente, sem criar outro projeto ou mudar seu plano. `kmuv2_models` contém somente associações para produtos novos. Os produtos continuam em `kmb_produtos`. Os pedidos e métricas são separados. A aprovação chama a rotina financeira existente `kmb_confirmar_venda_expressa`; não há segundo livro de vendas. Quantidades, venda, parcelas, cobrança de entrega, movimento de estoque e status são confirmados na mesma transação Postgres. O pagamento não é confirmado pelo aceite.

Os itens solicitados e os valores aprovados são preservados separadamente. Mudança de preço exige conferência explícita. Mudança de identidade do modelo exige nova revisão do cliente. Estoque e disponibilidade são revalidados no servidor. O identificador da solicitação e a chave da rotina financeira impedem aprovações repetidas.

## Permissões

A central usa as contas já autorizadas no Supabase pelo mecanismo existente `km_autorizado`. Não oferece cadastro de novos administradores. Os novos RPCs administrativos usam funções internas com verificação explícita de identidade. Funções públicas têm SECURITY INVOKER, permissões de execução explícitas e não expõem tabelas administrativas ao visitante. Os privilégios anteriores não são modificados.

A Edge Function `km-current-gateway` possui rotas públicas intencionais para catálogo, consulta de entrega, solicitação e eventos. Por isso, a verificação genérica de JWT do gateway é desativada. O navegador não recebe a chave privilegiada; apenas o servidor usa SUPABASE_SERVICE_ROLE_KEY nas rotas públicas estreitas. Toda administração continua autenticada nos RPCs. Taxas de entrega enviadas pelo cliente são ignoradas e recalculadas no servidor, reutilizando a API de entrega existente sem revelar a origem privada.

RLS sem políticas nas tabelas de métricas, diagnóstico e manutenção é intencional: acesso direto fica bloqueado e as operações passam pelos RPCs restritos. A auditoria do Supabase continua apontando avisos preexistentes em funções antigas e na configuração de proteção contra senhas vazadas; não foram alterados para evitar interferência no sistema anterior. Referências:
- https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable
- https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection

## Atualização e privacidade

A central recebe mudanças via Realtime nos pedidos e metadados, com atualização de segurança a cada 15 segundos enquanto visível. O catálogo atualiza a cada 30 segundos enquanto visível e confere novamente os dados na revisão. Uma solicitação não reserva estoque. Só administradores podem aceitar ou recusar. Solicitações pendentes vencem em 7 dias sem gerar venda; o histórico permanece.

Métricas opcionais dependem de consentimento. Buscas livres não são armazenadas; somente termos do cadastro são individualizados. Diagnósticos contêm códigos fixos, sem mensagens de exceção ou campos de atendimento. Os limites de solicitações usam hash com chave do endereço de rede, e não armazenam o IP em texto puro. Métricas são mantidas por até 90 dias e limpas nas rotinas de recebimento de eventos.

## Exportação e importação

O backup inclui os modelos atuais, fotos embutidas, configurações e histórico carregado desta operação, com SHA-256 para integridade. Não é um backup completo da conta Supabase, nem do sistema antigo. SHA-256 não autentica autoria e não cifra o arquivo. Guarde-o em local privado.

A importação aceita o formato desta versão e mostra prévia. Importa somente modelos; não recria pedidos, vendas ou pagamentos. Duplicidades e registros históricos são rejeitados. Modelos alterados após a cópia não são sobrescritos silenciosamente. As fotos existentes são reaproveitadas quando disponíveis; imagens novas recebem nomes únicos. Se a gravação dos dados falhar, a transação é revertida. Fotos já enviadas antes dessa falha podem ficar sem associação, mas fotos anteriores nunca são apagadas.

## Verificação

- Testes originais: `npm test` na raiz.
- Nova interface e finalização: `npm --prefix trial test`.
- `database/test-integration.sql`: executar exclusivamente em BEGIN/ROLLBACK. Verifica criação, duplicidade, aceite, recusa, preço divergente, frete reconciliado, esgotamento, privacidade e isolamento histórico. Nenhum dado de teste deve permanecer.
- Conferir as impressões digitais e contagens históricas antes/depois de qualquer publicação.

Os arquivos de SQL em `database/` documentam a evolução implantada. Não executar todos novamente sobre um banco já configurado. As migrações correspondentes ficam no histórico do Supabase. O código da Edge Function está em `edge/`.

## Gestão e histórico (revisão de 17/11/2026)

A central inclui estoque (busca e filtro por marca, entrada, conferência e nova opção/tamanho a partir de um modelo), vendas diretas com vários itens, clientes, recebimentos parciais, despesas, agenda de retornos, relatório por período, precificação, simulador de parcelamento, consulta de movimentos e impressão do resumo da venda. São extensões da operação atual: vendas e recebimentos chamam as rotinas financeiras existentes, com escopo verificado no servidor, controle de revisão e chave de idempotência. Não há segundo livro financeiro. Registro de pagamento exige confirmação administrativa.

O filtro por palavras na marca/modelo foi retirado: nomes não são uma classificação confiável de produtos. A separação por identificador da operação continua em vigor. Os modelos do catálogo aparecem no estoque do Business; adicionar uma opção/tamanho cria uma variação com quantidade independente. O catálogo agrupa marca/modelo e apresenta as opções sem expor a quantidade disponível na interface.

O backup anterior enviado pelo proprietário foi verificado pelo SHA-256 e preservado integralmente em `kmuv2_private.business_documents`, com acesso somente por RPC administrativo. O arquivo contém 41 vendas, 4 despesas, 4 produtos, 10 cadastros de catálogo, 12 imagens de modelos, 2 configurações e 1 comprovante. Não colocar esse arquivo no GitHub. Os quatro produtos anteriores não são ativados na nova operação. O histórico é somente consulta; não recria lançamentos, pagamentos ou estoque e mantém o arquivo original para download. Os dados antigos do Firebase não são alterados.

A importação de histórico aceita a cópia JSON do Business antigo, verifica a soma no navegador e pede revisão antes de preservar. O servidor limita tamanho, formato e autorização. O backup da nova central inclui também os arquivos históricos carregados, além dos modelos com fotos. A restauração operacional de modelos permanece separada da consulta histórica, para evitar duplicar vendas.

Verificação adicional: `tests/business.cjs` e `database/test-business.sql` (exclusivamente BEGIN/ROLLBACK). Testam estoque compartilhado, nova opção, revisões, venda direta, recebimento parcial idempotente, isolamento de histórico, acesso anônimo bloqueado e integridade da importação.
