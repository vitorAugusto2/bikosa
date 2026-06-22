------------------
-- ruptura_view --
------------------
-- medir ruptura historica por item e projeto, mostrando frequencia, recorrencia e situacao no último dia

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
    est.codigo AS codigo_sku,
    est.projeto AS nome_projeto,
    COALESCE(seg.segmentacao, "sem segmentacao") AS segmentacao_prioridade,
    est.saldo_em_estoque AS saldo_estoque,
    est.date AS data_registro_estoque,
    -- flag para identificar ruptura: 1 = com ruptura | 0 = sem ruptura
    CASE
      WHEN est.saldo_em_estoque = 0 THEN 1
      ELSE 0
    END AS flag_ruptura
  FROM `bikosa.bike_estoque.tb_estoque` AS est
  LEFT JOIN segmentacao_atual AS seg
    ON est.codigo = seg.codigo
   AND est.projeto = seg.projeto
),

base_eventos AS (
  -- identifica o inicio de um novo evento de ruptura: ocorre quando hoje esta em ruptura e ontem nao estava
  SELECT
    *,
    CASE
      WHEN flag_ruptura = 1
       AND COALESCE(
         LAG(flag_ruptura) OVER (
           PARTITION BY codigo_sku, nome_projeto
           ORDER BY data_registro_estoque
         ),
         0
       ) = 0
      THEN 1
      ELSE 0
    END AS inicio_evento_ruptura
  FROM base
),

resumo_ruptura AS (
  SELECT
    codigo_sku,
    nome_projeto,
    segmentacao_prioridade,
    -- total de dias zerados no período analisado
    COUNTIF(flag_ruptura = 1) AS dias_com_ruptura,
    -- taxa de ruptura = dias com ruptura / total de dias observados
    ROUND(SAFE_DIVIDE(COUNTIF(flag_ruptura = 1), COUNT(*)), 4) AS taxa_ruptura,
    -- primeira e ultima ocorrencia de ruptura no historico
    MIN(CASE WHEN flag_ruptura = 1 THEN data_registro_estoque END) AS primeira_data_ruptura,
    MAX(CASE WHEN flag_ruptura = 1 THEN data_registro_estoque END) AS ultima_data_ruptura,
    -- quantidade de vezes que o item entrou em ruptura
    SUM(inicio_evento_ruptura) AS qte_eventos_ruptura
  FROM base_eventos
  GROUP BY
    codigo_sku, nome_projeto, segmentacao_prioridade
),

ultimo_registro AS (
  SELECT
    codigo_sku,
    nome_projeto,
    segmentacao_prioridade,
    saldo_estoque,
    ROW_NUMBER() OVER (
      PARTITION BY codigo_sku, nome_projeto
      ORDER BY data_registro_estoque DESC
    ) AS rn
  FROM base
)

SELECT
  rsr.codigo_sku,
  rsr.nome_projeto,
  rsr.segmentacao_prioridade,
  rsr.dias_com_ruptura,
  rsr.taxa_ruptura,
  rsr.primeira_data_ruptura,
  rsr.ultima_data_ruptura,
  rsr.qte_eventos_ruptura,
  -- mostra a situacao atual do item no ultimo dia disponival da base
  CASE
    WHEN urg.saldo_estoque = 0 THEN "em ruptura"
    ELSE "disponivel"
  END AS status_ultimo_dia
FROM resumo_ruptura AS rsr
LEFT JOIN ultimo_registro AS urg ON rsr.codigo_sku = urg.codigo_sku
 AND rsr.nome_projeto = urg.nome_projeto
 AND rsr.segmentacao_prioridade = urg.segmentacao_prioridade
 AND urg.rn = 1
ORDER BY
  rsr.taxa_ruptura DESC,
  rsr.dias_com_ruptura DESC,
  rsr.qte_eventos_ruptura DESC;
