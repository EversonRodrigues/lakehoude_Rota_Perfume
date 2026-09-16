import { useEffect, useState } from 'react';
import { Alert, AlertDescription, AlertTitle, Badge, GenieChat, Skeleton } from '@databricks/appkit-ui/react';

type QuemSou = { email: string | null; local: boolean };

/**
 * A aba conversacional.
 *
 * O GenieChat ja renderiza o SQL gerado de cada resposta num bloco expansivel
 * -- e por isso que ele esta aqui em vez de um chat proprio. O que a tela
 * acrescenta e o que o componente nao sabe: QUEM esta perguntando, COMO a
 * consulta e executada, e o aviso de que a resposta e gerada por IA.
 */
export function PerguntarPage() {
  const [quemSou, setQuemSou] = useState<QuemSou | null>(null);
  const [erroIdentidade, setErroIdentidade] = useState<string | null>(null);

  useEffect(() => {
    let vivo = true;
    fetch('/api/quem-sou')
      .then((r) => (r.ok ? r.json() : Promise.reject(new Error(`HTTP ${r.status}`))))
      .then((d: QuemSou) => {
        if (vivo) setQuemSou(d);
      })
      .catch((e: unknown) => {
        if (vivo) setErroIdentidade(e instanceof Error ? e.message : 'falha desconhecida');
      });
    return () => {
      vivo = false;
    };
  }, []);

  return (
    <div className="space-y-4 w-full max-w-4xl mx-auto">
      <div>
        <h2 className="text-2xl font-bold text-foreground">Perguntar</h2>
        <p className="text-sm text-muted-foreground mt-1">
          O mesmo Genie da direção, agora dentro do produto. Uma definição, duas portas.
        </p>
      </div>

      {/* ---- Identidade: quem esta perguntando ---- */}
      <div className="flex flex-wrap items-center gap-2 text-sm">
        <span className="text-muted-foreground">Você está logado como</span>
        {erroIdentidade ? (
          <Badge variant="destructive">identidade indisponível</Badge>
        ) : quemSou === null ? (
          <Skeleton className="h-5 w-48" />
        ) : quemSou.local ? (
          <Badge variant="secondary">desenvolvimento local — sem OAuth</Badge>
        ) : (
          <Badge variant="secondary">{quemSou.email}</Badge>
        )}
      </div>

      {/* ---- O aviso permanente. Nao e enfeite: e o contrato com quem le. ---- */}
      <Alert>
        <AlertTitle>A resposta é gerada por IA — confira antes de levar para a reunião</AlertTitle>
        <AlertDescription className="space-y-1">
          <p>
            Cada resposta traz o <strong>SQL que a produziu</strong>, num bloco que você pode abrir. Abra sempre. O
            número que vai para a reunião é o que você conferiu, não o que apareceu na tela.
          </p>
          <p>
            A consulta é executada <strong>pelo service principal do aplicativo</strong>, não pelo seu usuário — todo
            mundo aqui enxerga exatamente o mesmo recorte de dados.
          </p>
          <p className="text-muted-foreground">
            Este espaço responde sobre a fila da semana, o score dos clientes, o desempenho do modelo e os retornos de
            ligação. A métrica de negócio é o ganho sobre ligar às cegas.
          </p>
        </AlertDescription>
      </Alert>

      {/* O alias `direcao` casa com o mapa `spaces` em server/server.ts. */}
      <div className="h-[min(600px,70vh)] border rounded-lg overflow-hidden">
        <GenieChat alias="direcao" />
      </div>
    </div>
  );
}
