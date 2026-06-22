# Análise de Estoque Segmentado
Este projeto analisa o comportamento do estoque de peças utilizadas em operações de bicicletas compartilhadas, buscando identificar **riscos operacionais**, **rupturas de estoque** e **oportunidades de redistribuição**.

A análise utiliza os dados históricos de estoque e segmentação de criticidade, com objetivo de responder as perguntas:
1. Onde ocorrem rupturas de estoque?
2. Quais itens são mais críticos para a operação?
3. Existem oportunidades de ressuprimento ou redistribuição?
4. Como melhorar a gestão de estoque baseada em criticidade?

## Estrutura do Projeto
	Dados brutos
	     ↓
	Base unificada (estoque + segmentação)
	     ↓
	Diagnóstico de ruptura
	     ↓
	Indicadores de decisão (ressuprimento/redistribuição)

## Fonte de Dados
Todas as tabelas brutas estão localizada na pasta `data\raw`.
As tabelas transformadas estão localizada em `data\trans`.

**Tabela Estoque (tb_estoque)**
* Tabela com registros diários de estoque.

| Campo              | Descrição             |
| ------------------ | --------------------- |
| `codigo`           | código do item        |
| `projeto`          | operação / cidade     |
| `saldo_em_estoque` | quantidade disponível |
| `date`             | data do registro      |

**Tabela Segmentação**
* Classifica itens de acordo com sua criticidade.

| Campo            | Descrição           |
| ---------------- | ------------------- |
| `codigo`         | código do item      |
| `projeto`        | projeto             |
| `segmentacao`    | criticidade         |
| `ingestion_date` | data de atualização |

* Segmentação segue a lógica:

| Segmento | Criticidade      |
| -------- | ---------------- |
| A        | crítico          |
| B        | alto impacto     |
| C        | impacto moderado |
| D        | baixo impacto    |

## Preparação dos Dados
Primeiro passo foi realizar uma **análise exploratória das duas tabelas** verificando consistência nos dados. Em seguida, foi construída uma **base unificada** entre as duas tabelas (`tb_segmentacao` e `tb_estoque`).

Para garantir a segmentação mais atual, foi utilizada a seguinte função de janela:
```sql
      ROW_NUMBER() OVER (
        PARTITION BY codigo, projeto
        ORDER BY ingestion_date DESC
      ) AS rn
    FROM `bikosa.bike_estoque.tb_segmentacao`
  WHERE rn = 1
```

Isso permite selecionar apenas o **registro mais recente de segmentação (data de injestão) para cada item e projeto**.

Após isso, foi aplicado `LEFT JOIN` entre as tabelas com as chaves `projeto + codigo`:

```sql
  FROM `bikosa.bike_estoque.tb_estoque` AS est
  LEFT JOIN segmentacao_atual AS seg 
  	ON est.codigo = seg.codigo
    AND est.projeto = seg.projeto
```

Itens sem segmentação foram mantidos na base e classificados como **"sem segmentacao"**.

Isso evita perda de informação, embora possa introduzir algum viés analítico.

O resultado da consulta `base_unificada.sql` é uma tabela utilizada para análises de ruptura, ressuprimento e redistribuição.

## Principais Métricas/Indicadores
* **Ruptura de estoque**
	- Item considerado como falta de estoque 
		```
		saldo_estoque = 0 
		```
	- Obs: não existem dados explícitos de demanda. Portanto não é possível comparar estoque com demanda esperada.
 
* **Taxa de Ruptura**
	- Percentual de dias com estoque zerado. Permitindo comparar itens com históricos diferentes.
	    ```
		taxa_ruptura = dias_com_ruptura / dias_total
		```
* **Eventos de ruptura**
  	- Um novo evento de ruptura ocorre quando:
  	  	```
  	    estoque hoje = 0
		estoque ontem > 0
		```
	- Isso identifica quando um item **entra novamente em ruptura**.

* **Consumo médio diário**
	- Como não há dados explícitos de consumo, foi estimado usando **variação negativa de estoque**.
		```
  		consumo médio = média das variações negativas
		```

* **Cobertura de estoque**
  	- Número estimado de dias que o estoque atual consegue sustentar.
  	  ```
      cobertura = estoque_atual / consumo_medio_diario
  	  ```

* **Ação de ressuprimento**
	- Itens com baixa cobertura devem ser priorizados para reposição.
	```
	Regra:
 		cobertura < 5 -> ressuprimento
 		5 < cobertura < 15 -> monitoramento
 		cobertura > 30 -> excesso
 	```

* **Sinal de redistribuição**
	- Identifica oportunidades de redistribuir estoque entre projetos.
	```
 	Regra:
		cobertura > 20 -> candidato a redistribuicao
 		sem oportunidade clara
	```

## Pontos Importantes
### **Ruptura em itens críticos**
Quando cruza ruptura por segmentação, se itens A estão em ruptura, isso é um problema muito mais grave que ruptura em itens C ou outros. Isso acontece porque a segmentação normalmente representa criticidade operacional.

<img width="1487" height="238" alt="image" src="https://github.com/user-attachments/assets/b4c51f91-d494-450c-b6b6-e1e8906c5e45" />


### **Muitos itens sem segmentação**
Atraves da consulta `status_segmentação.sql`, é identificado que grande parte do estoque (~85%) não possui classificação. Isso é ocasioando pela qualidade dos dados, gerando alguns problemas como:
* não sabemos quais itens são críticos
* difícil priorizar ressuprimento
* risco de ruptura em itens importantes

<img width="263" height="73" alt="image" src="https://github.com/user-attachments/assets/a5d9436e-c214-4b75-9c81-67151e6c1b19" />


### Oportunidade de redistribuição
Foram identificadas oportunidades de redistribuição entre projetos do mesmo item (FTB0143), onde determinados itens apresentam excesso em um local enquanto estão em ruptura em outro ou pouco estoque.

<img width="1214" height="143" alt="image" src="https://github.com/user-attachments/assets/5e33b429-7a23-4c4d-b7ab-29e8ef62b82b" />


## Respondendo as perguntas
### 1. Onde ocorrem rupturas de estoque?
As rupturas ocorrem quando o saldo de estoque é igual a zero, permitindo identificar principalmente:

* itens com maior frequência de ruptura
* itens com ruptura recorrente
* itens em ruptura no último registro da base

A consulta `ruptura_view.sql` permite priorizar os itens com maior risco.

### 2. Quais itens são mais críticos para a operação?
Itens classificados como segmento A são os mais críticos. Quando ocorre ruptura nesses itens, o impacto operacional é maior.

A consulta `ruptura_itens_a.sql` lista os itens críticos que estão em ruptura no último dia da base.

### 3. Existem oportunidades de ressuprimento ou redistribuição?
Sim, o ressuprimento acontece quando os itens estão com baixa cobertura que devem ser repostos rapidamente. Já redistribuição ocorre quando um item contem excesso e cobertura de dias alta.

A consulta `ressuprimento_redistribuicao.sql` identifica automaticamente esses casos.

### 4. Como melhorar a gestão de estoque baseada em criticidade?
Algumas melhorias possíveis:
* Melhorar a qualidade dos dados, identificando e classificando os itens sem segmentação.
* Monitorar indicares de estoque: saldo de estoque, taxa de ruptura, cobertura média e itens críticos em ruptura.
* Sempre redistribuir os estoque se possivel antes de realizar reposição.
