# K&M Business — evolução compatível

Esta entrega mantém os documentos e cálculos antigos, adiciona campos às novas vendas e reutiliza as coleções existentes. Não executa migração destrutiva nem altera regras de acesso do Firebase.

## Funções disponíveis

- Central de relacionamento: Meu dia, busca única, fichas de clientes, responsáveis, retornos, pedidos e mensagens revisadas antes de abrir o WhatsApp.
- Módulos de acesso: Início, Comercial, Estoque, Financeiro, Inteligência e Administração. O botão + abre ações rápidas em todas as telas.
- Venda: responsável informado, forma de pagamento combinada, taxas, despesas adicionais e resultado após custos. Repetir venda usa o produto e o preço atuais; produto cadastrado sem estoque não pode ser repetido pelo atalho.
- Rascunhos de campos salvos automaticamente neste navegador, separados por conta autenticada. Fotos precisam ser anexadas novamente. O rascunho é removido depois de salvar uma nova venda.
- Filtros locais salvos: busca, situação, responsável, datas e valores mínimo/máximo. Até 15 combinações por navegador/conta.
- Recebimento parcial de uma parcela em aberto, sem criar outra venda e sem mudar a soma das parcelas. Recebimentos parciais novos usam transação e recusam uma venda alterada durante o preenchimento.
- Relatório por período com resultado após custos das vendas, recebimentos efetivos, formas de pagamento, responsáveis e ranking de produtos. Comparação com o período anterior de igual duração.
- Alertas de reposição e cobertura estimada, calculada com as vendas registradas dos últimos 30 dias; identificação de estoque sem venda recente.
- Simulação de preço com custo, despesa por unidade, taxa percentual e margem sobre a venda.
- Entrada de estoque em lote e conferência física com justificativa. Cada operação nova grava produtos e seu registro em uma transação. A identificação da entrada evita repetir o acréscimo ao tentar novamente após perda da resposta de rede.
- Histórico de entradas e conferências feitas por este módulo. Entradas atualizam o custo unitário atual, sem alterar custos das vendas antigas e sem criar despesas financeiras automaticamente.

## Limites e próxima etapa no Firebase

A entrega não afirma que a sincronização antiga inteira passou a ser transacional. Outros fluxos e aparelhos com versões antigas ainda usam o salvamento anterior. Antes de prometer proteção global para a última unidade ou auditoria inviolável, é necessário atualizar todos os caminhos de escrita e aplicar regras compatíveis no servidor.

As contas de administrador e equipe precisam ser vinculadas aos usuários reais pelo UID, usando papéis definidos no servidor. Nenhum e-mail de usuário foi publicado neste repositório para simular autorização. Esconder um botão não é autorização.

Dependem dessa próxima etapa:

1. Permissões individuais efetivas e aprovação de operações críticas.
2. Reservas de estoque integradas à venda, cancelamento e liberação, com validação global contra excesso de venda.
3. Auditoria protegida, registro anterior e reversão segura de alterações/cancelamentos.
4. Migração da sincronização geral com idempotência e controle de concorrência para todos os caminhos, inclusive versões antigas.
5. Pedido com múltiplos produtos, devoluções e movimentações completas de todo o estoque, preservando o modelo histórico de vendas.
6. Contas a pagar integradas à previsão de caixa. A previsão existente de recebimentos não representa saldo disponível.

Os eventos operacionais das vendas novas não são uma auditoria protegida no servidor. Nenhuma data, taxa, responsável ou movimento histórico ausente foi inventado.

## Dados antigos e interpretação financeira

Taxas e despesas ausentes valem zero nos relatórios novos; responsável e forma de pagamento ausentes aparecem como não informados. O resultado da venda deduz custo do produto, taxas e despesas específicas. As despesas gerais são exibidas separadamente para evitar somar duas vezes uma reposição já incluída no custo da mercadoria. Esses indicadores não são saldo bancário nem lucro contábil oficial.

Lembretes são mostrados dentro da central; não há envio automático nem notificação com o site fechado. Rascunhos e filtros ficam no navegador. Fichas e tarefas compartilhadas dependem de login e das permissões atuais do projeto.

## Validação

Execute `npm ci` e `npm test` (Node 24).

Os testes usam dados fictícios e banco simulado. Cobrem navegação, clientes, rascunhos, venda, parcelas, estoque, mensagens, conflitos e repetição de transação após falha de rede. Não fazem login nem escrevem no banco real de clientes. A verificação visual e os fluxos autenticados em produção precisam ser conferidos na conta real.
