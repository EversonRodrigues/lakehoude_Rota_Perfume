<#
.SYNOPSIS
    Cria o catalogo lakehouse_rotaperfume no Unity Catalog.

.DESCRIPTION
    POR QUE ISTO NAO ESTA NO BUNDLE:
    no Databricks Free Edition o Default Storage esta ligado, e nessa
    configuracao a API do Unity Catalog RECUSA criar catalogo -- ela exige um
    MANAGED LOCATION que a conta gratuita nao tem:

        Error: Metastore storage root URL does not exist.
               Default Storage is enabled in your account. (400 INVALID_STATE)

    O comando SQL funciona; a API do bundle nao. Por isso o catalogo nasce aqui,
    por SQL, e o resto do catalogo (schemas + volume) e recurso do bundle em
    resources/catalogo.yml.

    Rode ANTES de `databricks bundle deploy`: o catalogo tem que existir antes
    do deploy criar os schemas dentro dele.

.PARAMETER DatabricksProfile
    Profile da CLI do Databricks. Obrigatorio -- nunca deixe implicito.

.EXAMPLE
    .\scripts\criar-catalogo.ps1 rotaperfumes
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$DatabricksProfile,

    [Parameter(Position = 1)]
    [string]$Catalog = 'lakehouse_rotaperfume'
)

$ErrorActionPreference = 'Stop'

$sql = @"
CREATE CATALOG IF NOT EXISTS $Catalog
COMMENT 'Lakehouse da Rota Perfume: bronze, silver e gold. Criado por codigo, nao por clique.'
"@

Write-Host "Criando catalogo '$Catalog' no profile '$DatabricksProfile'..." -ForegroundColor Cyan

databricks experimental aitools tools query $sql --profile $DatabricksProfile
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao criar o catalogo '$Catalog' (exit code $LASTEXITCODE)."
}

Write-Host "OK. Catalogo '$Catalog' existe." -ForegroundColor Green
Write-Host "Proximo passo: databricks bundle deploy --target dev --profile $DatabricksProfile"
