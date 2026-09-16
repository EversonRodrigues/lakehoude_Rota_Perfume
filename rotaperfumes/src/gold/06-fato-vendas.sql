-- =========================================================================
-- CONTRATO DA gold.fato_vendas  --  escrito ANTES do SQL, de proposito.
--
--   Granularidade : uma linha por ITEM de pedido.
--                   Escrever esta frase evita seis meses de discussao.
--
--   Filtro        : exclui pedido CANCELADO.
--                   NAO exclui devolucao.
--
--   Dimensoes     : data_pedido, ano, mes, canal, cliente_id, razao_social,
--                   segmento, cidade, vendedor_id, sku, categoria, marca,
--                   nota_olfativa
--
--   Metricas      : quantidade, preco_praticado, receita, custo, margem
--                   receita = quantidade * preco_praticado
--                   custo   = quantidade * custo_unitario
--                   margem  = receita - custo
--
--   Devolucao     : entra com quantidade e receita NEGATIVAS, sinalizada em
--                   `devolucao`.
--
-- POR QUE A DEVOLUCAO FICA DENTRO: se ficasse de fora, a gold somaria
-- R$ 103,6 mi e a silver R$ 102,3 mi -- R$ 1,26 milhao de diferenca entre duas
-- camadas do MESMO pipeline, e a reuniao viraria uma discussao sobre qual
-- sistema esta certo. Quem quiser o bruto pede explicitamente:
--     SUM(receita) FILTER (WHERE NOT devolucao)
--
-- Particionado por ano e mes: 24 particoes, que e o recorte de quase toda
-- consulta de negocio.
-- =========================================================================

CREATE OR REPLACE TABLE lakehouse_rotaperfume.gold.fato_vendas
PARTITIONED BY (ano, mes)
COMMENT 'Fato de vendas no grao de ITEM de pedido. Exclui pedido cancelado; mantem devolucao com valor negativo e flag. Soma exatamente o mesmo que silver.pedidos: R$ 102.303.828,05.'
AS
SELECT
  i.item_id,
  i.pedido_id,
  p.data_pedido,
  p.canal,
  p.cliente_id,
  c.razao_social,
  c.segmento,
  c.cidade,
  c.uf,
  p.vendedor_id,
  i.sku,
  pr.categoria,
  pr.marca,
  pr.nota_olfativa,
  i.quantidade,
  i.preco_praticado,
  i.devolucao,
  CAST(i.quantidade * i.preco_praticado AS DECIMAL(18,2))       AS receita,
  CAST(i.quantidade * pr.custo_unitario AS DECIMAL(18,2))       AS custo,
  CAST(i.quantidade * i.preco_praticado
       - i.quantidade * pr.custo_unitario AS DECIMAL(18,2))     AS margem,
  current_timestamp()                                           AS _processado_em,
  p.ano,
  p.mes
FROM lakehouse_rotaperfume.silver.itens_pedido i
JOIN lakehouse_rotaperfume.silver.pedidos   p  ON p.pedido_id = i.pedido_id
JOIN lakehouse_rotaperfume.silver.produtos  pr ON pr.sku = i.sku
JOIN lakehouse_rotaperfume.silver.clientes  c  ON c.cliente_id = p.cliente_id
WHERE NOT p.cancelado;

-- COMMENT de NEGOCIO, nao tecnico. Isto nao e capricho: e o que o Genie le para
-- escolher a coluna certa. Coluna sem comentario e coluna usada errado, com
-- confianca.
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN receita
  COMMENT 'Quantidade vezes preco praticado. NEGATIVA nas linhas de devolucao. Some sem filtro para ter a receita liquida da empresa.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN custo
  COMMENT 'Quantidade vezes custo unitario do produto. Custo de aquisicao apenas: nao inclui frete, comissao nem despesa operacional.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN margem
  COMMENT 'Receita menos custo do produto. Nao considera desconto comercial nem frete. Esta e a definicao unica de margem da empresa.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN devolucao
  COMMENT 'true quando o item foi devolvido -- a linha entra com quantidade e receita negativas. Para o bruto vendido use SUM(receita) FILTER (WHERE NOT devolucao).';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN quantidade
  COMMENT 'Pecas do item. NEGATIVA na devolucao, para que a soma de a quantidade liquida movimentada.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN preco_praticado
  COMMENT 'Preco efetivamente cobrado no item, ja com o desconto comercial aplicado. Pode diferir do preco de tabela do produto.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN data_pedido
  COMMENT 'Data do pedido, nao a da entrega nem a do pagamento. E a data que toda analise comercial usa.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN canal
  COMMENT 'Canal de entrada do pedido (Visita, WhatsApp, Televendas...). Vem do pedido, nao do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN segmento
  COMMENT 'Segmento do cliente no momento da consulta, nao no momento da venda: a dimensao nao guarda historico.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN razao_social
  COMMENT 'Razao social ja padronizada e deduplicada por CNPJ na silver.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN marca
  COMMENT 'Marca do produto vendido. Layali, Dahab e Nadir concentram a maior parte da receita.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN categoria
  COMMENT 'Categoria do produto. Determina o patamar de margem: Kit Presente margina perto de 33%, Oleo Concentrado perto de 50%.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN nota_olfativa
  COMMENT 'Nota olfativa dominante do produto (Cardamomo, Oud, Ambar...).';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN ano
  COMMENT 'Ano do pedido. Coluna de particao.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN mes
  COMMENT 'Mes do pedido, de 1 a 12. Coluna de particao.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN sku
  COMMENT 'Codigo do produto vendido. Chave para gold.dim_produto.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN cliente_id
  COMMENT 'Chave para gold.dim_cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN vendedor_id
  COMMENT 'Vendedor que registrou o pedido. Chave para gold.dim_vendedor.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN item_id
  COMMENT 'Identificador do item na origem. Uma linha do fato por item_id: e o grao declarado no contrato.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN pedido_id
  COMMENT 'Pedido a que o item pertence. Varias linhas do fato compartilham o mesmo pedido_id -- cerca de 6,9 em media.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN cidade
  COMMENT 'Cidade do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN uf
  COMMENT 'UF do cliente.';
ALTER TABLE lakehouse_rotaperfume.gold.fato_vendas ALTER COLUMN _processado_em
  COMMENT 'Momento em que esta linha foi (re)gerada pelo pipeline. Metadado tecnico, nunca metrica de negocio.';
