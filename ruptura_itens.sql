-------------------
-- ruptura_itens --
-------------------
-- Lista todos os itens criticos da segmentacao desejada do utlimo dia da base

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
    est.codigo                                   AS codigo_sku,
    est.projeto                                  AS nome_projeto,
    COALESCE(seg.segmentacao, "sem segmentacao") AS segmentacao_prioridade,
    est.saldo_em_estoque                         AS saldo_estoque,
    est.date                                     AS data_registro_estoque
  FROM `bikosa.bike_estoque.tb_estoque` AS est
  LEFT JOIN segmentacao_atual AS seg
    ON est.codigo = seg.codigo
   AND est.projeto = seg.projeto
),

ultimo_dia AS (
  -- pega a data mais recente da base
  SELECT MAX(data_registro_estoque) AS data_referencia
  FROM base
)

SELECT
  data_registro_estoque,
  nome_projeto,
  codigo_sku,
  segmentacao_prioridade,
  saldo_estoque
FROM base
CROSS JOIN ultimo_dia AS udi
WHERE data_registro_estoque = udi.data_referencia
  AND segmentacao_prioridade = "A" -- pode trocar por [B, C, D ou sem segmentacao]
  AND saldo_estoque = 0
ORDER BY
  nome_projeto,
  codigo_sku;
