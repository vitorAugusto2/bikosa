--------------------
-- base_unificada --
--------------------
-- Base principal do case, unindo estoque com a segmentacao na data mais recente e preservando itens "sem segmentacao"

WITH segmentacao_atual AS (
  SELECT
    codigo,
    projeto,
    segmentacao
  FROM (
    SELECT
      codigo,
      projeto,
      segmentacao,
      ingestion_date,
      -- pega a data (injestion_date) da segmentacao mais recente
      ROW_NUMBER() OVER (
        PARTITION BY codigo, projeto
        ORDER BY ingestion_date DESC
      ) AS rn
    FROM `bikosa.bike_estoque.tb_segmentacao`
  )
  WHERE rn = 1
),

base AS (
  SELECT
    est.codigo  AS codigo_sku,
    est.projeto AS nome_projeto,
    -- caso o item nao exista na tabela de segmentação, e mantido como "sem segmentacao"
    CASE
      WHEN seg.segmentacao IS NULL THEN "sem segmentacao"
      ELSE seg.segmentacao
    END AS segmentacao_prioridade,
    est.saldo_em_estoque AS saldo_estoque,
    est.date             AS data_registro_estoque
  FROM `bikosa.bike_estoque.tb_estoque` AS est
  LEFT JOIN segmentacao_atual AS seg -- nao perder os itens do estoque que ainda nao possuem segmentacao
    ON est.codigo = seg.codigo
   AND est.projeto = seg.projeto
)

SELECT *
FROM base;
