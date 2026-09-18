import { useMemo } from 'react';
import { useAnalyticsQuery, BarChart, useThemeColors } from '@databricks/appkit-ui/react';
import {
  Alert,
  AlertDescription,
  AlertTitle,
  Card,
  CardContent,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
  Skeleton,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@databricks/appkit-ui/react';
import { Kpi, KpisEsqueleto } from '../../components/Kpi';
import { dataHora, inteiro, num, porcento, reais, vezes } from '../../lib/formato';

/**
 * Quantos vendedores entram no grafico. Trinta e seis barras nao se leem: o
 * eixo vira um borrao de nomes e ninguem acha ninguem. Doze cabem na tela.
 *
 * O corte e DECLARADO embaixo do grafico -- um "top N" silencioso faz a tela
 * parecer completa quando nao e, e o diretor conclui que o resto do time nao
 * trabalhou.
 */
const TETO_GRAFICO = 12;

/**
 * Amostra minima para comparar a conversao com a taxa base do modelo.
 *
 * Com cinco ligacoes, uma venda vira "20% de conversao, 2x o modelo" -- uma
 * frase impressionante e sem nenhum conteudo. Abaixo deste piso a tela diz que
 * a amostra e pequena em vez de anunciar um lift que o proximo retorno derruba.
 */
const AMOSTRA_MINIMA = 30;

/** Os quatro desfechos, na ordem de leitura: do melhor ao que nem conversa teve. */
const DESFECHOS = [
  { chave: 'vendeu', rotulo: 'Vendeu', tom: 'text-foreground' },
  { chave: 'vai_pensar', rotulo: 'Vai pensar', tom: 'text-foreground' },
  { chave: 'sem_interesse', rotulo: 'Sem interesse', tom: 'text-muted-foreground' },
  { chave: 'nao_atendeu', rotulo: 'Não atendeu', tom: 'text-muted-foreground' },
] as const;

type Linha = Record<string, unknown>;

/** Soma uma coluna da consulta em todas as linhas, sempre passando por num(). */
function somar(linhas: Linha[], coluna: string): number {
  return linhas.reduce((s, l) => s + (num(l[coluna]) ?? 0), 0);
}

/**
 * Rotulo do vendedor para eixo e tabela.
 *
 * Dois vendedores desta base tem nome repetido (Henrique Oliveira, ids 34 e 36;
 * Vinicius Lopes, 31 e 37). Sem o id no rotulo o grafico mostra duas barras
 * visualmente identicas e o diretor cobra a pessoa errada. Mesma regra que
 * `vendedores.sql` aplica no filtro da outra aba.
 */
function rotularVendedores(linhas: Linha[]): Map<string, string> {
  const vezesONome = new Map<string, number>();
  for (const l of linhas) {
    const nome = String(l.vendedor);
    vezesONome.set(nome, (vezesONome.get(nome) ?? 0) + 1);
  }
  const rotulos = new Map<string, string>();
  for (const l of linhas) {
    const nome = String(l.vendedor);
    const id = String(l.vendedor_id);
    rotulos.set(id, (vezesONome.get(nome) ?? 0) > 1 ? `${nome} (${id})` : nome);
  }
  return rotulos;
}

/**
 * O desfecho da semana, por vendedor.
 *
 * Le `acompanhamento.sql` (contagem e valor por vendedor) e `kpis_semana.sql`
 * (a taxa base do modelo, para a conversao ter contra o que se medir).
 *
 * Enquanto ninguem registrou nada os numeros sao todos zero -- e zero NAO e
 * erro, e o estado inicial correto. Os cartoes aparecem mesmo assim, mostrando
 * 0% de cobertura e a fila inteira por ligar, porque "0 de 200" e uma
 * informacao de verdade; a tela so troca o grafico pela explicacao.
 */
export function AcompanhamentoPage() {
  const acomp = useAnalyticsQuery('acompanhamento');
  const kpis = useAnalyticsQuery('kpis_semana');

  const linhas = useMemo(() => (acomp.data ?? []) as Linha[], [acomp.data]);
  const rotulos = useMemo(() => rotularVendedores(linhas), [linhas]);

  // num() em tudo: o warehouse devolve numero como string, mesmo quando o tipo
  // gerado diz `number`. Somar sem isso concatena ("7" + "12" = "712").
  const naFila = somar(linhas, 'na_fila');
  const trabalhados = somar(linhas, 'trabalhados');
  const vendeu = somar(linhas, 'vendeu');
  const receitaFechada = somar(linhas, 'receita_fechada');
  const receitaAberta = somar(linhas, 'receita_aberta');
  const receitaEsperada = somar(linhas, 'receita_esperada');

  const aLigar = naFila - trabalhados;
  const cobertura = naFila > 0 ? trabalhados / naFila : null;
  const conversao = trabalhados > 0 ? vendeu / trabalhados : null;
  const emCampo = linhas.filter((l) => (num(l.trabalhados) ?? 0) > 0).length;
  const equipe = linhas.length;

  // A data do retorno mais novo, para o cabecalho dizer de quando e a tela.
  const ultimoEm = linhas
    .map((l) => l.ultimo_retorno_em)
    .filter((v): v is string => typeof v === 'string')
    .sort()
    .at(-1);

  // A taxa base do modelo: quanto da base compra em 7 dias sem ninguem ligar.
  // E o unico denominador honesto para dizer se a fila esta valendo a pena.
  // Se a consulta falhar, a tela segue sem a comparacao -- nao e motivo de erro.
  const taxaBase = num(kpis.data?.[0]?.taxa_base);
  const amostraBoa = trabalhados >= AMOSTRA_MINIMA;
  const lift = amostraBoa && conversao !== null && taxaBase ? conversao / taxaBase : null;

  if (acomp.error) {
    return (
      <div className="space-y-6 max-w-7xl mx-auto">
        <Cabecalho ultimoEm={undefined} />
        <Alert variant="destructive">
          <AlertTitle>Não consegui carregar o acompanhamento</AlertTitle>
          <AlertDescription>
            {acomp.error}
            {/permission/i.test(acomp.error)
              ? ' — isto costuma ser o service principal do app sem GRANT no schema gold.'
              : null}
          </AlertDescription>
        </Alert>
      </div>
    );
  }

  if (acomp.loading) {
    return (
      <div className="space-y-6 max-w-7xl mx-auto">
        <Cabecalho ultimoEm={undefined} />
        <KpisEsqueleto />
        <Skeleton className="h-[320px] w-full" />
      </div>
    );
  }

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      <Cabecalho ultimoEm={ultimoEm} />

      {/* ---- Os quatro numeros da semana ---- */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <Kpi
          titulo="Cobertura da fila"
          valor={cobertura === null ? '—' : porcento(cobertura, 1)}
          comparacao={`${inteiro(trabalhados)} de ${inteiro(naFila)} contatos trabalhados`}
          destaque={aLigar > 0 ? `Faltam ${inteiro(aLigar)} ligações` : 'Fila inteira trabalhada'}
          procedencia="gold.retorno_ligacao × gold.fila_semanal"
        />
        <Kpi
          titulo="Conversão real"
          valor={conversao === null ? '—' : porcento(conversao, 1)}
          comparacao={
            trabalhados === 0
              ? 'nenhuma ligação registrada ainda'
              : `${inteiro(vendeu)} ${vendeu === 1 ? 'pedido' : 'pedidos'} em ${inteiro(trabalhados)} trabalhados`
          }
          destaque={
            lift !== null
              ? `${vezes(lift)} a taxa base de ${porcento(taxaBase, 1)}`
              : trabalhados > 0
                ? `amostra pequena para comparar (mín. ${AMOSTRA_MINIMA})`
                : undefined
          }
          procedencia="denominador = trabalhados, não a fila inteira"
        />
        <Kpi
          titulo="Pedidos fechados"
          valor={inteiro(vendeu)}
          comparacao={`${reais(receitaFechada)} em ticket médio`}
          destaque={naFila > 0 ? `${porcento(vendeu / naFila, 1)} da fila de ${inteiro(naFila)}` : undefined}
          procedencia="estimativa: ticket médio histórico, não receita faturada"
        />
        <Kpi
          titulo="Vendedores em campo"
          valor={`${inteiro(emCampo)} de ${inteiro(equipe)}`}
          comparacao={
            equipe - emCampo > 0
              ? `${inteiro(equipe - emCampo)} ainda não registraram nada`
              : 'toda a equipe já registrou'
          }
          destaque={`${reais(receitaAberta)} em "vai pensar"`}
          procedencia={`fila estimada em ${reais(receitaEsperada)}`}
        />
      </div>

      {/* ---- A mistura dos desfechos ---- */}
      <DesfechoDaSemana linhas={linhas} trabalhados={trabalhados} />

      {trabalhados === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyTitle>Ninguém registrou retorno ainda</EmptyTitle>
            <EmptyDescription>
              São <strong>{inteiro(naFila)}</strong> contatos na fila desta semana, e nenhum foi marcado como
              trabalhado. O número aparece aqui assim que o time registrar o resultado das ligações na aba{' '}
              <em>A semana</em>.
              <br />
              <br />E isso não é só relatório:{' '}
              <strong>o que o time responde aqui vira o dado de treino da semana que vem</strong> — inclusive sobre quem
              não comprou porque ninguém ligou. Zero não é erro; é o começo.
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <GraficoPorVendedor linhas={linhas} rotulos={rotulos} />
      )}

      <TabelaPorVendedor linhas={linhas} rotulos={rotulos} />
    </div>
  );
}

/**
 * A mistura dos quatro desfechos, em porcentagem de quem foi trabalhado.
 *
 * Fica fora do grafico de proposito: e a leitura do time inteiro, nao a
 * comparacao entre pessoas. Com zero trabalhados mostra tracos, nao zeros --
 * "0%" sugere que alguem ligou e nao vendeu, e nao foi isso que aconteceu.
 */
function DesfechoDaSemana({ linhas, trabalhados }: { linhas: Linha[]; trabalhados: number }) {
  return (
    <Card>
      <CardContent className="grid gap-4 py-4 sm:grid-cols-2 lg:grid-cols-4">
        {DESFECHOS.map(({ chave, rotulo, tom }) => {
          const n = somar(linhas, chave);
          return (
            <div key={chave}>
              <p className="text-sm text-muted-foreground">{rotulo}</p>
              <p className={`text-2xl font-semibold tabular-nums ${tom}`}>
                {inteiro(n)}
                <span className="ml-2 text-sm font-normal text-muted-foreground">
                  {trabalhados > 0 ? porcento(n / trabalhados, 0) : '—'}
                </span>
              </p>
            </div>
          );
        })}
      </CardContent>
    </Card>
  );
}

/**
 * Barras HORIZONTAIS e EMPILHADAS, uma por vendedor.
 *
 * O grafico antigo era vertical com duas series lado a lado, e errava tres
 * coisas de uma vez:
 *
 *  1. trinta e seis nomes proprios num eixo X viram um borrao ilegivel;
 *  2. `vendeu` e um SUBCONJUNTO de `trabalhados` -- desenhados como irmaos, o
 *     olho soma os dois e conta a mesma ligacao duas vezes;
 *  3. quem ainda nao foi trabalhado simplesmente nao aparecia, entao a barra
 *     nao dizia o tamanho da fila daquela pessoa.
 *
 * Empilhado resolve os tres: o comprimento total da barra E a fila do vendedor,
 * e os pedacos sao as partes dela. A escala comeca em zero e as tres series
 * usam a mesma unidade (contatos), que e o que torna as barras comparaveis.
 *
 * Cor por INTENSIDADE, da paleta sequencial do tema -- nao hex fixo: mais forte
 * = desfecho melhor, e continua legivel no tema escuro.
 */
function GraficoPorVendedor({ linhas, rotulos }: { linhas: Linha[]; rotulos: Map<string, string> }) {
  const sequencial = useThemeColors('sequential');

  const ativos = useMemo(
    () =>
      linhas
        .filter((l) => (num(l.trabalhados) ?? 0) > 0)
        .sort(
          (a, b) => (num(b.vendeu) ?? 0) - (num(a.vendeu) ?? 0) || (num(b.trabalhados) ?? 0) - (num(a.trabalhados) ?? 0)
        ),
    [linhas]
  );

  const dados = useMemo(
    () =>
      ativos
        .slice(0, TETO_GRAFICO)
        // ECharts desenha a primeira categoria EMBAIXO no modo horizontal.
        // Sem o reverse o melhor vendedor fica no rodape do grafico.
        .reverse()
        .map((l) => {
          const naFila = num(l.na_fila) ?? 0;
          const trabalhados = num(l.trabalhados) ?? 0;
          const vendeu = num(l.vendeu) ?? 0;
          return {
            vendedor: rotulos.get(String(l.vendedor_id)) ?? String(l.vendedor),
            Vendeu: vendeu,
            'Sem venda': trabalhados - vendeu,
            'A ligar': naFila - trabalhados,
          };
        }),
    [ativos, rotulos]
  );

  const escondidos = ativos.length - dados.length;
  const cores = sequencial.length >= 8 ? [sequencial[7], sequencial[4], sequencial[1]] : undefined;

  return (
    <div className="space-y-2">
      <BarChart
        data={dados}
        xKey="vendedor"
        yKey={['Vendeu', 'Sem venda', 'A ligar']}
        orientation="horizontal"
        stacked
        colors={cores}
        title="A fila de cada vendedor: o que virou pedido, o que não virou, o que falta ligar"
        height={Math.max(240, 60 + dados.length * 34)}
      />
      <p className="text-xs text-muted-foreground">
        A barra inteira é a fila daquele vendedor. Só aparecem os {inteiro(ativos.length)} que já registraram algum
        retorno
        {escondidos > 0 ? (
          <>
            , e o gráfico mostra os {TETO_GRAFICO} com mais vendas —{' '}
            <strong>{inteiro(escondidos)} ficaram de fora</strong>, e estão na tabela abaixo
          </>
        ) : null}
        .
      </p>
    </div>
  );
}

/** A tabela completa: todos os vendedores, inclusive os que ainda não ligaram. */
function TabelaPorVendedor({ linhas, rotulos }: { linhas: Linha[]; rotulos: Map<string, string> }) {
  return (
    <div className="rounded-lg border overflow-x-auto">
      <Table className="table-fixed">
        <TableHeader>
          <TableRow>
            <TableHead className="w-[220px]">Vendedor</TableHead>
            <TableHead className="w-[90px] text-right">Na fila</TableHead>
            <TableHead className="w-[110px] text-right">Trabalhados</TableHead>
            <TableHead className="w-[90px] text-right">Vendeu</TableHead>
            <TableHead className="w-[140px] text-right">Fechado (est.)</TableHead>
            <TableHead className="w-[110px] text-right">Vai pensar</TableHead>
            <TableHead className="w-[120px] text-right">Sem interesse</TableHead>
            <TableHead className="w-[120px] text-right">Não atendeu</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {linhas.map((l) => (
            <TableRow key={String(l.vendedor_id)}>
              <TableCell className="whitespace-normal break-words">
                {rotulos.get(String(l.vendedor_id)) ?? String(l.vendedor)}
              </TableCell>
              <TableCell className="text-right tabular-nums">{inteiro(l.na_fila)}</TableCell>
              <TableCell className="text-right tabular-nums font-medium">{inteiro(l.trabalhados)}</TableCell>
              <TableCell className="text-right tabular-nums">{inteiro(l.vendeu)}</TableCell>
              <TableCell className="text-right tabular-nums">
                {(num(l.receita_fechada) ?? 0) > 0 ? reais(l.receita_fechada) : '—'}
              </TableCell>
              <TableCell className="text-right tabular-nums text-muted-foreground">{inteiro(l.vai_pensar)}</TableCell>
              <TableCell className="text-right tabular-nums text-muted-foreground">
                {inteiro(l.sem_interesse)}
              </TableCell>
              <TableCell className="text-right tabular-nums text-muted-foreground">{inteiro(l.nao_atendeu)}</TableCell>
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  );
}

function Cabecalho({ ultimoEm }: { ultimoEm: string | undefined }) {
  return (
    <div>
      <h2 className="text-2xl font-bold text-foreground">Acompanhamento</h2>
      <p className="text-sm text-muted-foreground mt-1">
        O que aconteceu depois da ligação, por vendedor.
        {ultimoEm ? <> Último retorno registrado em {dataHora(ultimoEm)}.</> : null}
      </p>
    </div>
  );
}
