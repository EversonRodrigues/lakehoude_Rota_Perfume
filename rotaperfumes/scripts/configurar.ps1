<#
.SYNOPSIS
    Cria os arquivos de variaveis locais do bundle a partir do modelo.

.DESCRIPTION
    O databricks.yml nao guarda e-mail nem id de warehouse -- eles sao variaveis
    sem default. Quem as preenche e o arquivo
    .databricks/bundle/<target>/variable-overrides.json, que o .gitignore exclui.

    Este script copia o modelo para dev e prod. Depois e so editar e preencher.
    Nao sobrescreve o que ja existe: rodar de novo e seguro.

.PARAMETER Force
    Sobrescreve os arquivos existentes, descartando o que voce ja preencheu.

.EXAMPLE
    .\scripts\configurar.ps1
#>
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

$raiz = Split-Path -Parent $PSScriptRoot
$modelo = Join-Path $raiz 'variable-overrides.exemplo.json'

if (-not (Test-Path $modelo)) {
    throw "Modelo nao encontrado: $modelo"
}

foreach ($target in @('dev', 'prod')) {
    $pasta = Join-Path $raiz ".databricks\bundle\$target"
    $destino = Join-Path $pasta 'variable-overrides.json'

    if ((Test-Path $destino) -and -not $Force) {
        Write-Host "ja existe, mantido: $destino" -ForegroundColor DarkGray
        continue
    }

    New-Item -ItemType Directory -Force -Path $pasta | Out-Null
    Copy-Item $modelo $destino -Force
    Write-Host "criado: $destino" -ForegroundColor Green
}

Write-Host ''
Write-Host 'Agora edite os dois arquivos e preencha workspace_user e warehouse_id.'
Write-Host 'Para descobrir os valores:'
Write-Host '  databricks current-user me --profile <perfil>'
Write-Host '  databricks warehouses list --profile <perfil>'
