import { createApp, analytics, genie, server, getExecutionContext } from '@databricks/appkit';
import { z } from 'zod';

/**
 * O backend do app da direcao.
 *
 * DUAS DIRECOES, DOIS CAMINHOS, e isso e desenho, nao acaso:
 *
 *   LEITURA e sempre um arquivo .sql em config/queries/, tipado pelo typegen e
 *   servido pelo plugin analytics. Nenhuma rota aqui executa SELECT.
 *
 *   ESCRITA e uma rota POST, uma so, com o conjunto de valores FECHADO por um
 *   enum no servidor. Se o front pudesse mandar `status` livre, em tres semanas
 *   a tabela teria "vendeu", "Vendeu", "vendido" e "VENDEU" -- e nenhuma conta
 *   de conversao fecharia mais.
 *
 * CONTEXTO DE EXECUCAO das leituras:
 *   - `<query>.sql`      roda como o SERVICE PRINCIPAL do app
 *   - `<query>.obo.sql`  roda como o USUARIO logado
 * Todas as quatro queries sao `.sql`, entao dependem dos GRANT dados ao service
 * principal: SELECT na gold, e MODIFY em UMA tabela so -- retorno_ligacao.
 */

const CATALOGO = 'lakehouse_rotaperfume';

/** Os quatro desfechos possiveis. Esta lista E o contrato do dado. */
const STATUS = ['vendeu', 'vai_pensar', 'sem_interesse', 'nao_atendeu'] as const;

const RetornoSchema = z.object({
  // z.coerce porque a tela manda o id que veio do warehouse, e ele chega como
  // STRING mesmo estando tipado como number no typegen.
  cliente_id: z.coerce.number().int(),
  vendedor: z.string().trim().min(1),
  status: z.enum(STATUS),
  comentario: z.string().trim().max(500).optional(),
  referencia: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'use o formato aaaa-mm-dd'),
});

await createApp({
  plugins: [
    analytics(),
    // O alias e explicito (regra de scaffolding do plugin), mas o id continua
    // vindo do ambiente: em producao ele e injetado pelo app.yaml a partir do
    // recurso `genie-space` declarado no databricks.yml.
    genie({
      spaces: {
        direcao: process.env.DATABRICKS_GENIE_SPACE_ID ?? '',
      },
    }),
    server(),
  ],

  // CACHE DESLIGADO, E TEM QUE SER AQUI NO TOPO.
  //
  // O plugin analytics cacheia resultado por 1 HORA e NAO le config propria:
  // `analytics({ cache: {...} })` compila e e silenciosamente ignorado. Só este
  // switch global funciona.
  //
  // Sem isto, alguem clica em "Vendeu" e a tela continua mostrando o numero de
  // antes por ate uma hora. Sao 200 linhas e todas mudam quando alguem clica:
  // tela certa vale mais que tela rapida.
  cache: { enabled: false },

  onPluginsReady(appkit) {
    appkit.server.extend((app) => {
      /**
       * Quem esta olhando a tela.
       *
       * O header `x-forwarded-email` e posto pelo proxy do Databricks Apps a
       * partir do login OAuth -- nao da para o cliente forjar. Em
       * `npm run dev`, rodando fora da plataforma, ele NAO existe: por isso o
       * fallback explicito, e por isso a tela sabe distinguir os dois casos.
       */
      app.get('/api/quem-sou', (req, res) => {
        res.json(quemSou(req.header('x-forwarded-email'), req.header('x-forwarded-user')));
      });

      /**
       * O CAMINHO DE VOLTA: o resultado da ligacao vira linha na gold.
       *
       * O handler tem `try/catch` PROPRIO de proposito. O `server.extend`
       * registra direto no Express, e o Express NAO encaminha rejeicao de
       * Promise para o middleware de erro -- sem o catch, uma falha do
       * warehouse viraria requisicao pendurada ate o timeout do navegador.
       */
      app.post('/api/retorno', async (req, res) => {
        // 1) O contrato primeiro. Corpo invalido nao chega a tocar no warehouse.
        const parsed = RetornoSchema.safeParse(req.body);
        if (!parsed.success) {
          res.status(400).json({
            erro: 'Corpo invalido.',
            aceitos: STATUS,
            detalhe: z.flattenError(parsed.error).fieldErrors,
          });
          return;
        }
        const r = parsed.data;

        try {
          const { client, warehouseId } = getExecutionContext();

          // `warehouseId` e uma Promise E e opcional -- ela so existe quando um
          // plugin declara o recurso SQL_WAREHOUSE. Tratar em vez de deixar
          // estourar um erro de tipo ilegivel no log.
          const wid = await warehouseId;
          if (!wid) {
            res.status(500).json({
              erro: 'Nenhum SQL warehouse configurado para este app.',
            });
            return;
          }

          const registradoPor =
            quemSou(req.header('x-forwarded-email'), req.header('x-forwarded-user')).email ?? 'desenvolvimento-local';

          // TODO valor vai por `parameters`, nunca concatenado na string: é o
          // que impede injecao de SQL. `registrado_em` sai do relogio do
          // WAREHOUSE, nao do cliente -- o navegador de quem clica nao e fonte
          // confiavel de horario.
          const resposta = await client.statementExecution.executeStatement({
            warehouse_id: wid,
            wait_timeout: '30s',
            on_wait_timeout: 'CANCEL',
            statement: `
              INSERT INTO ${CATALOGO}.gold.retorno_ligacao
                (cliente_id, vendedor, status, comentario,
                 registrado_em, registrado_por, _referencia)
              VALUES (:cliente_id, :vendedor, :status, :comentario,
                      current_timestamp(), :registrado_por, :referencia)
            `,
            parameters: [
              { name: 'cliente_id', type: 'INT', value: String(r.cliente_id) },
              { name: 'vendedor', type: 'STRING', value: r.vendedor },
              { name: 'status', type: 'STRING', value: r.status },
              // `value` omitido = NULL. Registrar o desfecho sem comentar e valido.
              { name: 'comentario', type: 'STRING', ...(r.comentario ? { value: r.comentario } : {}) },
              { name: 'registrado_por', type: 'STRING', value: registradoPor },
              { name: 'referencia', type: 'DATE', value: r.referencia },
            ],
          });

          const estado = resposta.status?.state;
          if (estado !== 'SUCCEEDED') {
            res.status(502).json({
              erro: 'O warehouse nao concluiu a gravacao.',
              detalhe: resposta.status?.error?.message ?? estado ?? 'estado desconhecido',
            });
            return;
          }

          res.status(201).json({ gravado: true, registrado_por: registradoPor });
        } catch (e: unknown) {
          const detalhe = e instanceof Error ? e.message : String(e);
          console.error('[retorno] falha ao gravar:', detalhe);
          res.status(500).json({ erro: 'Nao consegui gravar o retorno.', detalhe });
        }
      });
    });
  },
});

/** Normaliza os headers de identidade numa resposta só, usada em dois lugares. */
function quemSou(email?: string, usuario?: string): { email: string | null; local: boolean } {
  const e = (email ?? usuario ?? '').trim();
  // `local` = rodando fora da plataforma, sem OAuth no meio.
  return { email: e || null, local: e === '' };
}
