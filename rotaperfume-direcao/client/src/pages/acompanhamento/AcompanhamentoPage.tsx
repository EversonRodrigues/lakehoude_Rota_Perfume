import { useAnalyticsQuery, BarChart } from '@databricks/appkit-ui/react';
import {
  Alert,
  AlertDescription,
  AlertTitle,
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
import { inteiro, num } from '../../lib/formato';

/**
 * O desfecho da semana, por vendedor.
 *
 * Le `acompanhamento.sql`, que foi escrito na entrega anterior justamente para
 * esta tela existir hoje sem tocar em SQL de novo.
 *
 * Enquanto ninguem registrou nada, os numeros sao todos zero -- e zero NAO e
 * erro, e o estado inicial correto. A tela diz isso em vez de parecer quebrada.
 */
export function AcompanhamentoPage() {
  const acomp = useAnalyticsQuery('acompanhamento');
  const linhas = acomp.data ?? [];

  // num() em tudo: o warehouse devolve numero como string.
  const naFila = linhas.reduce((s, l) => s + (num(l.na_fila) ?? 0), 0);
  const trabalhados = linhas.reduce((s, l) => s + (num(l.trabalhados) ?? 0), 0);
  const vendeu = linhas.reduce((s, l) => s + (num(l.vendeu) ?? 0), 0);

  if (acomp.error) {
    return (
      <div className="space-y-6 max-w-7xl mx-auto">
        <Cabecalho />
        <Alert variant="destructive">
          <AlertTitle>Não consegui carregar o acompanhamento</AlertTitle>
          <AlertDescription>{acomp.error}</AlertDescription>
        </Alert>
      </div>
    );
  }

  if (acomp.loading) {
    return (
      <div className="space-y-6 max-w-7xl mx-auto">
        <Cabecalho />
        <Skeleton className="h-6 w-96" />
        <Skeleton className="h-[320px] w-full" />
      </div>
    );
  }

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      <Cabecalho />

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
        <>
          <p className="text-base text-foreground">
            <strong>{inteiro(trabalhados)}</strong> dos <strong>{inteiro(naFila)}</strong> contatos já foram
            trabalhados, e <strong>{inteiro(vendeu)}</strong> {vendeu === 1 ? 'virou pedido' : 'viraram pedido'}.
          </p>

          {/* ECharts: configura por PROPS, nunca por filhos no estilo Recharts. */}
          <BarChart
            queryKey="acompanhamento"
            xKey="vendedor"
            yKey={['trabalhados', 'vendeu']}
            title="Trabalhados e vendas por vendedor"
            height={340}
          />

          <div className="rounded-lg border overflow-x-auto">
            <Table className="table-fixed">
              <TableHeader>
                <TableRow>
                  <TableHead className="w-[220px]">Vendedor</TableHead>
                  <TableHead className="w-[90px] text-right">Na fila</TableHead>
                  <TableHead className="w-[110px] text-right">Trabalhados</TableHead>
                  <TableHead className="w-[90px] text-right">Vendeu</TableHead>
                  <TableHead className="w-[110px] text-right">Vai pensar</TableHead>
                  <TableHead className="w-[120px] text-right">Sem interesse</TableHead>
                  <TableHead className="w-[120px] text-right">Não atendeu</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {linhas.map((l) => (
                  <TableRow key={String(l.vendedor_id)}>
                    <TableCell className="whitespace-normal break-words">{l.vendedor}</TableCell>
                    <TableCell className="text-right tabular-nums">{inteiro(l.na_fila)}</TableCell>
                    <TableCell className="text-right tabular-nums font-medium">{inteiro(l.trabalhados)}</TableCell>
                    <TableCell className="text-right tabular-nums">{inteiro(l.vendeu)}</TableCell>
                    <TableCell className="text-right tabular-nums text-muted-foreground">
                      {inteiro(l.vai_pensar)}
                    </TableCell>
                    <TableCell className="text-right tabular-nums text-muted-foreground">
                      {inteiro(l.sem_interesse)}
                    </TableCell>
                    <TableCell className="text-right tabular-nums text-muted-foreground">
                      {inteiro(l.nao_atendeu)}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </>
      )}
    </div>
  );
}

function Cabecalho() {
  return (
    <div>
      <h2 className="text-2xl font-bold text-foreground">Acompanhamento</h2>
      <p className="text-sm text-muted-foreground mt-1">O que aconteceu depois da ligação, por vendedor.</p>
    </div>
  );
}
