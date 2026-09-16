/**
 * Formatacao em portugues do Brasil -- e a defesa contra a armadilha numero 1
 * desta tela.
 *
 * O WAREHOUSE DEVOLVE NUMERO COMO STRING no JSON, mesmo quando o tipo gerado
 * pelo typegen diz `number`. O tipo descreve o SCHEMA da coluna; o runtime
 * entrega texto. As duas consequencias, as duas medidas:
 *
 *   "556423.71".toLocaleString('pt-BR')  ->  "556423.71"   (nao formata nada)
 *   "7" + "12"                           ->  "712"         (concatena)
 *
 * Por isso TUDO passa por num() antes de formatar ou somar. Nao e defensividade
 * exagerada: e o comportamento real do transporte.
 */

/** Converte o que veio do warehouse em numero. NaN e null viram `null`. */
export function num(v: unknown): number | null {
  if (v === null || v === undefined || v === '') return null;
  const n = typeof v === 'number' ? v : Number(v);
  return Number.isFinite(n) ? n : null;
}

/** Inteiro com separador de milhar: 200 -> "200", 1234 -> "1.234". */
export function inteiro(v: unknown): string {
  const n = num(v);
  return n === null ? '—' : n.toLocaleString('pt-BR', { maximumFractionDigits: 0 });
}

/** Reais com duas casas: 556423.71 -> "R$ 556.423,71". */
export function reais(v: unknown): string {
  const n = num(v);
  if (n === null) return '—';
  return n.toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
}

/**
 * Score (0 a 1) como porcentagem inteira: 0.9740085224443632 -> "97%".
 * Ninguem decide ligacao lendo dezesseis casas decimais.
 */
export function porcento(v: unknown, casas = 0): string {
  const n = num(v);
  if (n === null) return '—';
  return `${(n * 100).toLocaleString('pt-BR', {
    minimumFractionDigits: casas,
    maximumFractionDigits: casas,
  })}%`;
}

/** Multiplicador do modelo: 4.148421 -> "4,15x". */
export function vezes(v: unknown): string {
  const n = num(v);
  if (n === null) return '—';
  return `${n.toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}×`;
}

/** Data curta a partir do timestamp que o warehouse devolve como texto ISO. */
export function dataCurta(v: unknown): string {
  // Aceita so o que da para virar data de verdade. `String(objeto)` produziria
  // "[object Object]" e um "Invalid Date" silencioso.
  if (typeof v !== 'string' && typeof v !== 'number' && !(v instanceof Date)) return '—';
  const d = v instanceof Date ? v : new Date(v);
  return Number.isNaN(d.getTime())
    ? '—'
    : d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', year: 'numeric' });
}

/**
 * Data no formato aaaa-mm-dd, que e o que a rota POST /api/retorno exige.
 * Recorta direto do texto ISO que o warehouse devolve, sem passar por Date --
 * `new Date(...).toISOString()` converteria para UTC e poderia virar o dia.
 */
export function dataISO(v: unknown): string | null {
  if (typeof v !== 'string') return null;
  const m = /^(\d{4}-\d{2}-\d{2})/.exec(v);
  return m ? m[1] : null;
}

/** Rotulo em portugues para o status do retorno da ligacao. */
export const ROTULO_STATUS: Record<string, string> = {
  vendeu: 'Vendeu',
  vai_pensar: 'Vai pensar',
  sem_interesse: 'Sem interesse',
  nao_atendeu: 'Não atendeu',
};
