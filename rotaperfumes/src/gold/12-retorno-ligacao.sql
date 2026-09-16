-- =========================================================================
-- O CAMINHO DE VOLTA
--
-- Tres noites construiram o caminho de IDA: arquivo -> bronze -> silver ->
-- gold -> modelo -> as 200 ligacoes da semana. Em nenhum ponto desse caminho o
-- pipeline fica sabendo o que aconteceu DEPOIS da ligacao. Ele sabe a quem
-- ligar e nunca descobre se vendeu.
--
-- Esta e a unica tabela do projeto cujo dado NAO vem do pipeline -- vem do
-- time, uma linha por ligacao registrada na tela. Por isso, e so por isso, ela
-- e a unica com CREATE TABLE IF NOT EXISTS: um redeploy nao pode apagar o que
-- o vendedor respondeu. Todas as outras sao CREATE OR REPLACE porque podem ser
-- reconstruidas a partir da origem; esta nao pode.
--
-- Ela nasce VAZIA, e vazia e o estado correto no comeco. Zero retorno nao e
-- bug: e a pergunta que ninguem tinha como responder ate hoje.
--
-- CHAVE: nao existe chave unica. Um cliente pode ter varios retornos ao longo
-- do tempo -- para o estado ATUAL, pegue o mais recente por registrado_em.
-- E nunca agrupe por `vendedor`: nome de vendedor NAO e unico nesta base (dois
-- Henrique Oliveira, dois Vinicius Lopes). O nome aqui e o que a tela mandou,
-- serve para exibir, nao para identificar.
-- =========================================================================

CREATE TABLE IF NOT EXISTS lakehouse_rotaperfume.gold.retorno_ligacao (
  cliente_id     INT       COMMENT 'Cliente que foi contatado. Casa com gold.fila_semanal.cliente_id e com gold.dim_cliente.',
  vendedor       STRING    COMMENT 'Nome do vendedor que registrou, como veio da tela. Serve para EXIBIR: nome de vendedor nao e unico nesta base, entao nunca agrupe metrica por esta coluna.',
  status         STRING    COMMENT 'Resultado da ligacao, conjunto fechado: vendeu, vai_pensar, sem_interesse ou nao_atendeu. Conversao e status = ''vendeu''.',
  comentario     STRING    COMMENT 'Texto livre do vendedor sobre a conversa. Pode ser nulo -- registrar o resultado sem comentar e valido.',
  registrado_em  TIMESTAMP COMMENT 'Momento do registro. E o criterio de desempate quando o mesmo cliente tem mais de um retorno: o estado atual e o mais recente.',
  registrado_por STRING    COMMENT 'E-mail de quem estava logado no app quando gravou. Vem do header de identidade, nao de campo preenchido a mao -- por isso serve de auditoria.',
  _referencia    DATE      COMMENT 'Semana da fila a que este retorno responde. Liga a linha a versao de gold.fila_semanal que gerou o contato.'
)
COMMENT 'O que aconteceu depois da ligacao. Unica tabela do projeto alimentada pelo time e nao pelo pipeline, e por isso a unica com IF NOT EXISTS: redeploy nao apaga resposta de vendedor. Nasce vazia de proposito. Um cliente pode ter varios retornos -- para o estado atual use o mais recente por registrado_em.';
