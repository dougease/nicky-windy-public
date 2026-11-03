# Instala a rotina de 72 h sem mudar a ação da tarefa agendada existente.
$ErrorActionPreference = 'Stop'
$dados = if ($env:NICKY_ANALYTICS_DIR) {
    $env:NICKY_ANALYTICS_DIR
} else {
    'C:\Users\Douglas\Documents\NICKY OOH\Climatologia'
}
$repo = if ($env:NICKY_WINDY_PUBLIC_REPO) {
    $env:NICKY_WINDY_PUBLIC_REPO
} else {
    Join-Path $dados 'Nicky_Windy_Public\automacao\repo'
}
$origem = Join-Path $repo 'scripts\atualizar_windy_nicky_72h.R'
$gerador = Join-Path $repo 'scripts\gerar_windy_72h.R'
$publicadorNovo = Join-Path $repo 'scripts\sincronizar-windy-72h.ps1'
$publicadorAtual = Join-Path $dados 'sincronizar-windy.ps1'
$destino = Join-Path $dados 'atualizar_windy_nicky.R'
$necessarios = @(
    $origem, $gerador, $publicadorNovo, $publicadorAtual, $destino,
    (Join-Path $dados 'previsao_rajadas_ecmwf_janelas.csv'),
    (Join-Path $dados 'previsao_rajadas_gefs_janelas.csv'),
    (Join-Path $dados 'paineis_previsao_3.xlsx'),
    (Join-Path $dados 'paineis_previsao_gefs.xlsx'),
    (Join-Path $dados 'nicky_windy_monitoramento.R'),
    (Join-Path $dados 'Nicky_Analytics_Shiny\www\windy\paineis_nicky.geojson'),
    (Join-Path $repo 'docs\windy\index.html')
)
$ausentes = @($necessarios | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
if ($ausentes.Count -gt 0) {
    throw "Instalação cancelada. Arquivos ausentes:`n$($ausentes -join "`n")"
}
if (-not (Test-Path -LiteralPath (Join-Path $repo '.git') -PathType Container)) {
    throw "Instalação cancelada: repositório Git não encontrado em $repo"
}
$rscript = Get-Command Rscript.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Source
if (-not $rscript) {
    $candidatos = @(Get-ChildItem -Path 'C:\Program Files\R\R-*\bin\Rscript.exe' -ErrorAction SilentlyContinue)
    if ($candidatos.Count -gt 0) { $rscript = $candidatos[-1].FullName }
}
if (-not $rscript) {
    throw 'Rscript.exe não foi encontrado. A rotina atual foi preservada.'
}
& $rscript -e "parse(file=commandArgs(trailingOnly=TRUE)[1]); parse(file=commandArgs(trailingOnly=TRUE)[2])" $origem $gerador
if ($LASTEXITCODE -ne 0) {
    throw 'Falha na conferência de sintaxe R. A rotina atual foi preservada.'
}
$carimbo = Get-Date -Format 'yyyyMMdd_HHmmss'
$backup = "$destino.backup_$carimbo"
$backupPublicador = "$publicadorAtual.backup_$carimbo"
Copy-Item -LiteralPath $destino -Destination $backup -ErrorAction Stop
Copy-Item -LiteralPath $publicadorAtual -Destination $backupPublicador -ErrorAction Stop
try {
    Copy-Item -LiteralPath $origem -Destination $destino -Force -ErrorAction Stop
    Copy-Item -LiteralPath $publicadorNovo -Destination $publicadorAtual -Force -ErrorAction Stop
} catch {
    Copy-Item -LiteralPath $backup -Destination $destino -Force
    Copy-Item -LiteralPath $backupPublicador -Destination $publicadorAtual -Force
    throw
}
Write-Host "Rotina 72 h instalada: $destino"
Write-Host "Cópia de segurança: $backup"
Write-Host "Publicador atualizado: $publicadorAtual"
Write-Host "Cópia de segurança: $backupPublicador"
Write-Host 'O agendamento não foi alterado. Execute a tarefa Atualização Windy para validar a próxima rodada.'
