# Acesso e limitações temporárias

`auth/too-many-requests` é uma resposta do Firebase Authentication que indica limitação temporária após excesso de pedidos ou atividade considerada incomum. Somente os registros do serviço permitem determinar o motivo específico para uma conta, aparelho ou rede. Não há diagnóstico de senha incorreta baseado apenas nesse código.

A interface aceita somente uma operação de autenticação em andamento, desabilita Entrar/Criar conta enquanto espera, valida os campos antes de requisitar e não tenta novamente automaticamente. Ao receber `auth/too-many-requests`, pausa novos envios desta aba por 60 segundos. Essa pausa é apenas da interface: **não remove nem determina a duração da limitação do Firebase**, que pode durar mais.

A pausa persiste no `sessionStorage` como um prazo numérico, sem e-mail ou senha. Erros conhecidos recebem mensagens claras e mantêm o código para diagnóstico. Os dados das vendas e a configuração do Firebase não são alterados.

Os testes de autenticação usam respostas simuladas, sem tentativas em contas reais. `npm test` verifica validação, bloqueio de cliques simultâneos, limitação temporária, ausência de novas tentativas automáticas, erros de conexão/credenciais e preservação dos dados.
