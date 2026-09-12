<#
.SYNOPSIS
    Sobe os 10 CSVs de dados/erp e dados/crm para o Volume bronze.raw.

.DESCRIPTION
    Raw nao e bronze. Raw e arquivo; bronze e tabela. Este script coloca o CSV
    no Volume do Unity Catalog exatamente como ele saiu do ERP/CRM, byte por
    byte -- para que "esse numero veio de onde?" tenha como resposta um arquivo,
    nao uma opiniao.

    Por que Volume e nao DBFS: Volume e objeto do Unity Catalog -- tem dono, tem
    permissao, aparece na linhagem. DBFS e uma pasta sem sobrenome.

    Rode DEPOIS de `databricks bundle deploy`: o Volume precisa existir antes de
    receber arquivo.

    ATENCAO ao destino: `databricks fs cp` exige o esquema `dbfs:` mesmo quando
    o destino e um Volume do UC. Sem ele o comando reclama do caminho.

.PARAMETER DatabricksProfile
    Profile da CLI do Databricks. Obrigatorio -- nunca deixe implicito.

.EXAMPLE
    .\scripts\subir-raw.ps1 rotaperfumes
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$DatabricksProfile,

    [Parameter(Position = 1)]
    [string]$Catalog = 'lakehouse_rotaperfume'
)

$ErrorActionPreference = 'Stop'

# scripts/ -> raiz do bundle -> raiz do repositorio, onde vive dados/
$raizRepo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$origem   = Join-Path $raizRepo 'dados'

if (-not (Test-Path $origem)) {
    throw "Pasta de origem nao encontrada: $origem. Os CSVs de ERP/CRM precisam estar em dados/erp e dados/crm na raiz do repositorio."
}

foreach ($sistema in @('erp', 'crm')) {
    $pastaLocal = Join-Path $origem $sistema
    if (-not (Test-Path $pastaLocal)) {
        throw "Pasta de origem nao encontrada: $pastaLocal"
    }

    $destino = "dbfs:/Volumes/$Catalog/bronze/raw/$sistema"
    $qtd = (Get-ChildItem -Path $pastaLocal -Filter *.csv).Count
    Write-Host "Subindo $qtd arquivo(s) de $pastaLocal -> $destino" -ForegroundColor Cyan

    databricks fs cp $pastaLocal $destino --recursive --overwrite --profile $DatabricksProfile
    if ($LASTEXITCODE -ne 0) {
        throw "Falha ao subir '$sistema' para $destino (exit code $LASTEXITCODE)."
    }
}

Write-Host "OK. Raw no Volume." -ForegroundColor Green
Write-Host "Confira com: databricks fs ls dbfs:/Volumes/$Catalog/bronze/raw/erp --profile $DatabricksProfile"
