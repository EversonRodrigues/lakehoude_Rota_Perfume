import { Card, CardContent, CardHeader, CardTitle, Skeleton } from '@databricks/appkit-ui/react';

/**
 * Um cartao de KPI. O AppKit NAO exporta KpiCard -- compomos de primitivas.
 *
 * As quatro partes sao obrigatorias de proposito. Um numero sozinho na tela nao
 * informa nada: `comparacao` diz contra o que ele se mede e `procedencia` diz de
 * onde ele saiu. Numero sem denominador e sem fonte e o jeito mais rapido de
 * uma reuniao inteira discutir a coisa errada.
 */
export function Kpi({
  titulo,
  valor,
  comparacao,
  procedencia,
  destaque,
}: {
  titulo: string;
  valor: string;
  comparacao: string;
  procedencia: string;
  /** Segunda linha opcional, para a leitura que exige ressalva (amostra, lift). */
  destaque?: string;
}) {
  return (
    <Card>
      <CardHeader className="pb-2">
        <CardTitle className="text-sm font-medium text-muted-foreground">{titulo}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-1">
        <div className="text-3xl font-semibold tabular-nums text-foreground">{valor}</div>
        <p className="text-sm text-muted-foreground">{comparacao}</p>
        {destaque ? <p className="text-sm font-medium text-foreground">{destaque}</p> : null}
        <p className="text-xs text-muted-foreground/70">{procedencia}</p>
      </CardContent>
    </Card>
  );
}

/** Esqueleto com a mesma grade dos cartoes, para o estado de carregamento. */
export function KpisEsqueleto({ quantos = 4 }: { quantos?: number }) {
  return (
    <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
      {Array.from({ length: quantos }, (_, i) => (
        <Card key={i}>
          <CardHeader className="pb-2">
            <Skeleton className="h-4 w-32" />
          </CardHeader>
          <CardContent className="space-y-2">
            <Skeleton className="h-9 w-24" />
            <Skeleton className="h-4 w-28" />
          </CardContent>
        </Card>
      ))}
    </div>
  );
}
