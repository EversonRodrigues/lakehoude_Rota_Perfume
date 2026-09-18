import { useMemo, useState } from 'react';
import { useAnalyticsQuery } from '@databricks/appkit-ui/react';
import { sql } from '@databricks/appkit-ui/js';
import {
  Alert,
  AlertDescription,
  AlertTitle,
  Badge,
  Button,
  Empty,
  EmptyDescription,
  EmptyHeader,
  EmptyTitle,
  Input,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Skeleton,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@databricks/appkit-ui/react';
import { Kpi, KpisEsqueleto } from '../../components/Kpi';
import { dataCurta, dataISO, inteiro, num, porcento, reais, ROTULO_STATUS, vezes } from '../../lib/formato';

const TODOS = 'Todos';

/** Os quatro desfechos, na ordem em que aparecem na linha. O servidor valida de novo. */
const STATUS: { valor: string; rotulo: string }[] = [
  { valor: 'vendeu', rotulo: 'Vendeu' },
  { valor: 'vai_pensar', rotulo: 'Vai pensar' },
  { valor: 'sem_interesse', rotulo: 'Sem interesse' },
  { valor: 'nao_atendeu', rotulo: 'Não atendeu' },
];

/**
 * O PAI. Guarda tudo que precisa SOBREVIVER a uma gravacao: o filtro escolhido,
 * os comentarios ja digitados nas outras linhas, e o contador de recarga.
 *
 * Por que um contador: `useAnalyticsQuery` NAO tem refetch. A unica alavanca
 * para repetir a consulta e remontar quem a chama -- e e isso que a `key` faz.
 *
 * A alternativa tentadora seria um parametro falso no SQL (`:recarga >= 0`).
 * NAO faca: quem estiver com a aba aberta de uma versao anterior passa a mandar
 * a consulta sem esse parametro, e o warehouse recusa com
 * UNBOUND_SQL_PARAMETER. A tela quebra sozinha depois de um deploy.
 */
export function SemanaPage() {
  const [vendedorId, setVendedorId] = useState<string>(TODOS);
  const [comentarios, setComentarios] = useState<Record<string, string>>({});
  const [recarga, setRecarga] = useState(0);
  const [erro, setErro] = useState<string | null>(null);

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      <div>
        <h2 className="text-2xl font-bold text-foreground">A semana</h2>
        <p className="text-sm text-muted-foreground mt-1">
          As 200 ligações que o modelo escolheu, e quanto elas valem.
        </p>
      </div>

      {erro ? (
        <Alert variant="destructive">
          <AlertTitle>Não consegui registrar o retorno</AlertTitle>
          <AlertDescription>{erro}</AlertDescription>
        </Alert>
      ) : null}

      <ConteudoSemana
        key={recarga}
        vendedorId={vendedorId}
        aoTrocarVendedor={setVendedorId}
        comentarios={comentarios}
        aoEscreverComentario={(id, texto) => setComentarios((c) => ({ ...c, [id]: texto }))}
        aoGravar={() => {
          setErro(null);
          setRecarga((n) => n + 1);
        }}
        aoFalhar={setErro}
      />
    </div>
  );
}

function ConteudoSemana({
  vendedorId,
  aoTrocarVendedor,
  comentarios,
  aoEscreverComentario,
  aoGravar,
  aoFalhar,
}: {
  vendedorId: string;
  aoTrocarVendedor: (v: string) => void;
  comentarios: Record<string, string>;
  aoEscreverComentario: (clienteId: string, texto: string) => void;
  aoGravar: () => void;
  aoFalhar: (mensagem: string) => void;
}) {
  // Qual linha esta gravando agora -- para desabilitar so ela, nao a tabela toda.
  const [gravando, setGravando] = useState<string | null>(null);

  const kpis = useAnalyticsQuery('kpis_semana');
  const vendedores = useAnalyticsQuery('vendedores');

  // useMemo obrigatorio: um objeto novo a cada render refaz a query em loop.
  const parametrosFila = useMemo(() => ({ vendedor_id: sql.string(vendedorId) }), [vendedorId]);
  const fila = useAnalyticsQuery('fila', parametrosFila);

  const k = kpis.data?.[0];
  const linhas = fila.data ?? [];

  // TUDO passa por num(): o warehouse entrega numero como string.
  const contatos = num(k?.contatos) ?? 0;
  const acertos = num(k?.acertos_top200) ?? 0;
  const conversaoPrevista = contatos > 0 ? acertos / contatos : null;
  const retornos = num(k?.retornos) ?? 0;
  const viraramPedido = num(k?.viraram_pedido) ?? 0;
  const referencia = dataCurta(k?.referencia);
  const referenciaISO = dataISO(k?.referencia);

  const nomeVendedorSelecionado =
    vendedorId === TODOS
      ? null
      : (vendedores.data?.find((v) => String(v.vendedor_id) === vendedorId)?.rotulo ?? vendedorId);

  async function registrar(clienteId: string, vendedor: string, status: string) {
    if (!referenciaISO) {
      aoFalhar('Não sei a qual semana este retorno pertence — os indicadores ainda não carregaram.');
      return;
    }
    setGravando(clienteId);
    try {
      const comentario = (comentarios[clienteId] ?? '').trim();
      const resposta = await fetch('/api/retorno', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          // Number() de proposito: o id chega do warehouse como string.
          cliente_id: Number(clienteId),
          vendedor,
          status,
          ...(comentario ? { comentario } : {}),
          referencia: referenciaISO,
        }),
      });
      if (!resposta.ok) {
        const corpo: unknown = await resposta.json().catch(() => null);
        const detalhe =
          corpo && typeof corpo === 'object' && 'erro' in corpo
            ? String((corpo as { erro: unknown }).erro)
            : `HTTP ${resposta.status}`;
        aoFalhar(detalhe);
        return;
      }
      aoGravar();
    } catch (e: unknown) {
      aoFalhar(e instanceof Error ? e.message : 'Falha de rede ao gravar o retorno.');
    } finally {
      setGravando(null);
    }
  }

  return (
    <>
      {/* ---- Os quatro numeros ---- */}
      {kpis.error ? (
        <Alert variant="destructive">
          <AlertTitle>Não consegui carregar os indicadores</AlertTitle>
          <AlertDescription>
            {kpis.error}
            {/permission/i.test(kpis.error)
              ? ' — isto costuma ser o service principal do app sem GRANT no schema gold.'
              : null}
          </AlertDescription>
        </Alert>
      ) : kpis.loading || !k ? (
        <KpisEsqueleto />
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <Kpi
            titulo="Contatos da semana"
            valor={inteiro(k.contatos)}
            comparacao={`${inteiro(k.vendedores)} vendedores`}
            procedencia={`fila de ${referencia}`}
          />
          <Kpi
            titulo="Receita esperada"
            valor={reais(k.receita_esperada)}
            comparacao="estimativa — soma de chance × ticket médio"
            procedencia="não é receita realizada"
          />
          <Kpi
            titulo="Conversão prevista"
            valor={porcento(conversaoPrevista)}
            comparacao={`${porcento(k.taxa_base, 1)} ligando às cegas`}
            procedencia={`ganho de ${vezes(k.lift_top200)} · modelo v${inteiro(k.versao_modelo)}`}
          />
          <Kpi
            titulo="Já trabalhados"
            valor={inteiro(retornos)}
            comparacao={retornos === 0 ? 'ninguém registrou retorno ainda' : `${inteiro(viraramPedido)} viraram pedido`}
            procedencia="gold.retorno_ligacao"
          />
        </div>
      )}

      {/* ---- Filtro ---- */}
      <div className="flex flex-wrap items-center gap-3">
        <span className="text-sm text-muted-foreground">Vendedor</span>
        <Select value={vendedorId} onValueChange={aoTrocarVendedor}>
          <SelectTrigger className="w-[280px]">
            <SelectValue placeholder="Todos os vendedores" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value={TODOS}>Todos os vendedores</SelectItem>
            {(vendedores.data ?? []).map((v) => (
              // A chave e o vendedor_id, nunca o nome: ha homonimos nesta base,
              // e `rotulo` ja traz o id quando o nome se repete.
              <SelectItem key={String(v.vendedor_id)} value={String(v.vendedor_id)}>
                {v.rotulo} · {inteiro(v.contatos)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
        {!fila.loading && !fila.error ? (
          <span className="text-sm text-muted-foreground">
            {inteiro(linhas.length)} {linhas.length === 1 ? 'contato' : 'contatos'}
          </span>
        ) : null}
      </div>

      {/* ---- A fila ---- */}
      {fila.error ? (
        <Alert variant="destructive">
          <AlertTitle>Não consegui carregar a fila</AlertTitle>
          <AlertDescription>{fila.error}</AlertDescription>
        </Alert>
      ) : fila.loading ? (
        <div className="space-y-2">
          {Array.from({ length: 8 }, (_, i) => (
            <Skeleton key={i} className="h-12 w-full" />
          ))}
        </div>
      ) : linhas.length === 0 ? (
        <Empty>
          <EmptyHeader>
            <EmptyTitle>Nenhum contato para {nomeVendedorSelecionado ?? 'este filtro'}</EmptyTitle>
            <EmptyDescription>
              A fila é <strong>global</strong>: são os 200 melhores scores da base inteira, não uma cota por vendedor.
              Quem tem carteira quente nesta semana recebe mais contatos — e quem não aparece aqui não tem nenhum
              cliente entre os 200. Isso é o sistema funcionando, não um erro.
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      ) : (
        <div className="rounded-lg border overflow-x-auto">
          <Table className="table-fixed">
            <TableHeader>
              <TableRow>
                <TableHead className="w-[60px]">Ordem</TableHead>
                <TableHead className="w-[220px]">Cliente</TableHead>
                <TableHead className="w-[150px]">Vendedor</TableHead>
                <TableHead className="w-[80px] text-right">Chance</TableHead>
                <TableHead className="w-[280px]">Por que ligar</TableHead>
                <TableHead className="w-[260px]">O que oferecer</TableHead>
                <TableHead className="w-[300px]">Como foi a ligação</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {linhas.map((l) => {
                const clienteId = String(l.cliente_id);
                const estaGravando = gravando === clienteId;
                return (
                  <TableRow key={`${l.vendedor_id}-${clienteId}`}>
                    <TableCell className="tabular-nums text-muted-foreground">{inteiro(l.ordem)}</TableCell>
                    <TableCell className="whitespace-normal break-words">
                      <div className="font-medium text-foreground">{l.razao_social}</div>
                      <div className="text-xs text-muted-foreground">
                        {l.cidade}/{l.uf} · ticket {reais(l.ticket_medio)}
                      </div>
                    </TableCell>
                    <TableCell className="whitespace-normal break-words">{l.vendedor}</TableCell>
                    <TableCell className="text-right tabular-nums font-medium">{porcento(l.score)}</TableCell>
                    <TableCell className="whitespace-normal break-words text-sm">{l.motivo}</TableCell>
                    <TableCell className="whitespace-normal break-words text-sm text-muted-foreground">
                      {l.sugestao}
                    </TableCell>
                    <TableCell className="whitespace-normal break-words">
                      {l.retorno_status ? (
                        // Ja registrado: mostra o desfecho, sem botoes. Registrar
                        // duas vezes o mesmo cliente confunde a leitura da fila.
                        <div className="space-y-1">
                          <Badge variant={l.retorno_status === 'vendeu' ? 'default' : 'secondary'}>
                            {ROTULO_STATUS[l.retorno_status] ?? l.retorno_status}
                          </Badge>
                          {l.retorno_comentario ? (
                            <p className="text-xs text-muted-foreground">{l.retorno_comentario}</p>
                          ) : null}
                        </div>
                      ) : (
                        <div className="space-y-2">
                          <Input
                            value={comentarios[clienteId] ?? ''}
                            onChange={(e) => aoEscreverComentario(clienteId, e.target.value)}
                            placeholder="Comentário (opcional)"
                            maxLength={500}
                            disabled={estaGravando}
                            className="h-8 text-xs"
                          />
                          <div className="flex flex-wrap gap-1">
                            {STATUS.map((s) => (
                              <Button
                                key={s.valor}
                                size="sm"
                                variant={s.valor === 'vendeu' ? 'default' : 'outline'}
                                disabled={estaGravando}
                                onClick={() => void registrar(clienteId, l.vendedor, s.valor)}
                                className="h-7 px-2 text-xs"
                              >
                                {s.rotulo}
                              </Button>
                            ))}
                          </div>
                        </div>
                      )}
                    </TableCell>
                  </TableRow>
                );
              })}
            </TableBody>
          </Table>
        </div>
      )}
    </>
  );
}
