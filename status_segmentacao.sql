------------------------
-- status_segmentacao --
------------------------
-- medir a cobertura de segmentacao da base de estoque,
-- identificando quantos itens estao com ou sem classificao/segmentacao

-- SELECT
--   COUNT(DISTINCT est.codigo) AS codigo_estoque,
--   COUNT(DISTINCT seg.codigo) AS codigo_segmentacao
-- FROM
--     `bikosa.bike_estoque.tb_estoque` AS est
--     LEFT JOIN `bikosa.bike_estoque.tb_segmentacao` AS seg
--       ON est.codigo = seg.codigo AND est.projeto = seg.projeto;

SELECT
  CASE
    WHEN seg.segmentacao IS NULL THEN "sem segmentacao"
    ELSE "segmentacao"
  END AS status,
  COUNT(DISTINCT est.codigo) AS qte_codigo_sku,
FROM
    `bikosa.bike_estoque.tb_estoque` AS est
    LEFT JOIN `bikosa.bike_estoque.tb_segmentacao` AS seg
     ON est.codigo = seg.codigo AND est.projeto = seg.projeto
GROUP BY
  status;
