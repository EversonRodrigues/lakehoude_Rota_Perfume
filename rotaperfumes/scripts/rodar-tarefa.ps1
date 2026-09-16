<#
.SYNOPSIS
    Roda UMA tarefa do rotaperfume_pipeline, sem rodar o pipeline inteiro.

.DESCRIPTION
    POR QUE ISTO EXISTE:
    o job tem 15 tarefas e uma execucao completa custa vários minutos de
    serverless, quase todos em cold start. Quando voce mexeu num unico .sql,
    rodar o DAG inteiro so para ver aquela tarefa e desperdicio -- e, ao vivo,
    e tempo de tela parada.

    `--json '{"only":["<tarefa>"]}'` executa a tarefa ISOLADA: as dependencias
    NAO rodam, elas sao assumidas como ja materializadas. Isso e exatamente o
    que voce quer para ver um teste falhar de proposito (a auditoria de
    metadado, por exemplo), e exatamente o que voce NAO quer quando a tarefa
    depende de dado que acabou de mudar upstream.

    O job_id sai do `bundle summary` do target, entao o script sempre acerta o
    job do ambiente em que voce esta -- nunca um id copiado de outro workspace.

.PARAMETER DatabricksProfile
    Profile da CLI do Databricks. Obrigatorio -- nunca deixe implicito.

.PARAMETER Tarefa
    task_key da tarefa, como esta em resources/pipeline.job.yml.
    Ex.: raw_conferencia, bronze_ingestao, silver_clientes, gold_dimensoes,
         gold_fato_vendas, gold_marts, gold_retorno_ligacao, testes,
         ml_features, ml_modelo, ml_fila, auditoria_de_metadado.

.PARAMETER Target
    Target do bundle. Default: dev.

.EXAMPLE
    .\scripts\rodar-tarefa.ps1 rotaperfumes auditoria_de_metadado

.EXAMPLE
    .\scripts\rodar-tarefa.ps1 rotaperfumes gold_retorno_ligacao
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$DatabricksProfile,

    [Parameter(Mandatory = $true, Position = 1)]
    [string]$Tarefa,

    [Parameter(Position = 2)]
    [string]$Target = 'dev'
)

$ErrorActionPreference = 'Stop'

Write-Host "Lendo o job_id do bundle (target '$Target', profile '$DatabricksProfile')..." -ForegroundColor Cyan

$resumoBruto = databricks bundle summary --target $Target --profile $DatabricksProfile --output json
if ($LASTEXITCODE -ne 0) {
    throw "Falha no 'bundle summary' (exit code $LASTEXITCODE). Rode de dentro de rotaperfumes/."
}

$resumo = $resumoBruto | ConvertFrom-Json
$jobId  = $resumo.resources.jobs.rotaperfume_pipeline.id
if (-not $jobId) {
    throw "Nao achei o rotaperfume_pipeline no bundle. Faca 'databricks bundle deploy' antes."
}

# Confere o task_key ANTES de disparar: a API aceita um 'only' inexistente e o
# run termina sem executar nada, verde e vazio -- o pior resultado possivel.
$tarefas = $resumo.resources.jobs.rotaperfume_pipeline.tasks.task_key
if ($tarefas -and ($tarefas -notcontains $Tarefa)) {
    throw "Tarefa '$Tarefa' nao existe no job. Tarefas: $($tarefas -join ', ')"
}

Write-Host "job_id $jobId -- rodando SO a tarefa '$Tarefa' (dependencias nao rodam)..." -ForegroundColor Cyan

# DUAS ARMADILHAS, as duas medidas aqui:
#
# 1. Com --json a CLI NAO aceita o job_id posicional -- ele tem que estar DENTRO
#    do JSON, senao vem "when --json flag is specified, no positional arguments
#    are allowed".
# 2. Passar o JSON INLINE nao funciona no Windows: o PowerShell come as aspas ao
#    repassar para um executavel nativo e a CLI responde
#    "error decoding JSON at (inline):1:2: invalid character 'j'".
#    A saida e gravar num arquivo e usar a sintaxe --json @arquivo.
# 3. E o arquivo nao pode ter BOM. `Set-Content -Encoding utf8` no PowerShell
#    5.1 escreve BOM, e a CLI reclama de
#    "invalid character 'ï' looking for beginning of value" -- os tres bytes do
#    BOM lidos como texto. Por isso o UTF8Encoding($false) explicito.
$payload = @{ job_id = $jobId; only = @($Tarefa) } | ConvertTo-Json -Compress
$arquivo = Join-Path ([System.IO.Path]::GetTempPath()) "rodar-tarefa-$PID.json"
[System.IO.File]::WriteAllText($arquivo, $payload, (New-Object System.Text.UTF8Encoding $false))

try {
    # O run-now devolve o run inteiro (as 15 tarefas, com as 14 puladas). Só
    # interessa a que foi pedida -- o resto é ruído numa demo ao vivo.
    $bruto = databricks jobs run-now --json "@$arquivo" --profile $DatabricksProfile
    $codigo = $LASTEXITCODE
}
finally {
    Remove-Item $arquivo -ErrorAction SilentlyContinue
}

if ($bruto) {
    try {
        $run = ($bruto | Out-String | ConvertFrom-Json)
        $esta = $run.tasks | Where-Object { $_.task_key -eq $Tarefa }
        Write-Host "  run: $($run.run_page_url)"
        if ($esta) {
            Write-Host "  resultado: $($esta.state.result_state)  ($([int]($esta.execution_duration / 1000))s)"
        }
    }
    catch {
        # run-now falhado imprime texto, nao JSON: mostre como veio.
        Write-Host ($bruto | Out-String)
    }
}
if ($codigo -ne 0) {
    Write-Host "A tarefa '$Tarefa' FALHOU (exit code $codigo)." -ForegroundColor Red
    Write-Host "Abra o run acima e leia a mensagem do raise_error -- ela nomeia o problema." -ForegroundColor Red
    exit $codigo
}

Write-Host "OK. Tarefa '$Tarefa' passou." -ForegroundColor Green
