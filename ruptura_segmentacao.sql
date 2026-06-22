-------------------------
-- ruptura_segmentacao --
-------------------------
-- Quantidade e taxa de ruptura por segmentacao do ultimo dia

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
    est.codigo  AS codigo_sku,
    est.projeto AS nome_projeto,
    COALESCE(seg.segmentacao, "sem segmentacao") AS segmentacao_prioridade,
    est.saldo_em_estoque AS saldo_estoque,
    est.date             AS data_registro_estoque
  FROM `bikosa.bike_estoque.tb_estoque` AS est
  LEFT JOIN segmentacao_atual AS seg ON est.codigo = seg.codigo AND est.projeto = seg.projeto
)

SELECT
  segmentacao_prioridade,
  COUNT(*) AS total_registros,
  COUNTIF(saldo_estoque = 0) AS registros_em_ruptura,
  ROUND(SAFE_DIVIDE(COUNTIF(saldo_estoque = 0), COUNT(*)) * 100, 2) AS taxa_ruptura
FROM base
GROUP BY segmentacao_prioridade
ORDER BY taxa_ruptura DESC;
