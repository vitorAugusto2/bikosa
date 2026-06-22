----------------------------------
-- ressuprimento_redistribuicao --
----------------------------------
-- Usando o estoque atual e um consumo medio estimado a partir da variacao diaria

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
    est.date AS data_registro_estoque
  FROM `bikosa.bike_estoque.tb_estoque` AS est
  LEFT JOIN segmentacao_atual AS seg
    ON est.codigo = seg.codigo
   AND est.projeto = seg.projeto
),

variacoes AS (
  SELECT
    data_registro_estoque,
    codigo_sku,
    nome_projeto,
    segmentacao_prioridade,
    saldo_estoque,
    -- variacao diaria do estoque dos itens
    saldo_estoque
      - LAG(saldo_estoque) OVER (
          PARTITION BY codigo_sku, nome_projeto
          ORDER BY data_registro_estoque
        ) AS variacao_estoque
  FROM base
),

consumo AS (
  SELECT
    codigo_sku,
    nome_projeto,
    segmentacao_prioridade,
    -- nao tem dados de demanda/consumo, intao cria uma media de variacoes
    AVG(ABS(variacao_estoque)) AS consumo_medio_diario
  FROM variacoes
  WHERE variacao_estoque < 0
  GROUP BY
    codigo_sku, nome_projeto, segmentacao_prioridade
),

estoque_atual AS (
  SELECT
    codigo_sku,
    nome_projeto,
    segmentacao_prioridade,
    saldo_estoque AS estoque_atual,
    data_registro_estoque
  FROM (
    SELECT
      codigo_sku,
      nome_projeto,
      segmentacao_prioridade,
      saldo_estoque,
      data_registro_estoque,
      ROW_NUMBER() OVER (
        PARTITION BY codigo_sku, nome_projeto
        ORDER BY data_registro_estoque DESC
      ) AS rn
    FROM base
  )
  WHERE rn = 1
),

base_acao AS (
  SELECT
    esa.codigo_sku,
    esa.nome_projeto,
    esa.segmentacao_prioridade,
    esa.estoque_atual,
    ROUND(COALESCE(con.consumo_medio_diario, 0), 2) AS consumo_medio_diario,
    -- cobertura em dias = estoque atual / consumo medio diario
    ROUND(
      SAFE_DIVIDE(
        esa.estoque_atual,
        NULLIF(COALESCE(con.consumo_medio_diario, 0), 0)
      ),
      2
    ) AS cobertura_dias
  FROM estoque_atual AS esa
  LEFT JOIN consumo AS con
    ON esa.codigo_sku = con.codigo_sku
   AND esa.nome_projeto = con.nome_projeto
),

redistribuicao AS (
  SELECT
    codigo_sku,
    -- compara o mesmo SKU entre projetos para identificar sobra e falta
    MAX(estoque_atual) AS maior_estoque_mesmo_codigo,
    MIN(estoque_atual) AS menor_estoque_mesmo_codigo
  FROM base_acao
  GROUP BY codigo_sku
)

SELECT
  bsa.codigo_sku,
  bsa.nome_projeto,
  bsa.segmentacao_prioridade,
  bsa.estoque_atual,
  bsa.consumo_medio_diario,
  bsa.cobertura_dias,
  -- regra de ressuprimento:
  -- * segmentacao = A e estoque = 0 ou dias cobertos < 5 -> urgente
  -- * estoque = 0 -> imediato
  -- * estoque NULL ou > 0 -> sem historico de consumo
  -- * cobertura_dias entre 5 a 15 dias -> monitorar
  -- * cobertura_dias > 45 -> excesso
  -- * senao saudavel
  CASE
    WHEN bsa.estoque_atual = 0 AND bsa.segmentacao_prioridade = "A" THEN "ressuprimento urgente"
    WHEN bsa.estoque_atual = 0 THEN "ressuprimento imediato"
    WHEN bsa.cobertura_dias IS NULL AND bsa.estoque_atual > 0 THEN "sem historico de consumo"
    WHEN bsa.cobertura_dias < 5 THEN "ressuprimento urgente"
    WHEN bsa.cobertura_dias BETWEEN 5 AND 15 THEN "monitorar ressuprimento"
    WHEN bsa.cobertura_dias > 45 THEN "excesso de estoque"
    ELSE "estoque saudavel"
  END AS acao_ressuprimento,
  CASE
    -- sinaliza oportunidade de redistribuir quando o mesmo SKU tem sobra em um projeto e falta em outro
    -- regra de redistribuição
    -- * cobertura de dias > 20 -> canditado a redistribuição
    -- * senao -> sem oportunidade clara
    WHEN res.maior_estoque_mesmo_codigo > 20
         AND res.menor_estoque_mesmo_codigo = 0
         AND bsa.estoque_atual = res.maior_estoque_mesmo_codigo
      THEN "candidato a redistribuicao"
    ELSE "sem oportunidade clara"
  END AS sinal_redistribuicao
FROM base_acao AS bsa
LEFT JOIN redistribuicao AS res
  ON bsa.codigo_sku = res.codigo_sku
ORDER BY
  acao_ressuprimento,
  sinal_redistribuicao,
  bsa.segmentacao_prioridade,
  bsa.codigo_sku,
  bsa.nome_projeto;
