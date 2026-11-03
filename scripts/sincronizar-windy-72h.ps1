[CmdletBinding()]
param(
    [string]$Source = 'C:\Users\Douglas\Documents\NICKY OOH\Climatologia\Nicky_Analytics_Shiny\www\windy\paineis_nicky.geojson',
    [string]$WorkingDirectory,
    [string]$JsonSource,
    [switch]$Interactive,
    [switch]$ValidateOnly
)
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = New-Object Text.UTF8Encoding $false
$OutputEncoding = [Console]::OutputEncoding
if (-not $WorkingDirectory) { $WorkingDirectory = Join-Path $PSScriptRoot '..\work\windy-public' }
function Read-GeoJson([string]$Text) {
    $j = $Text | ConvertFrom-Json
    if ($j.type -cne 'FeatureCollection' -or @($j.features).Count -eq 0) { throw 'GeoJSON vazio ou tipo incorreto.' }
    foreach ($f in $j.features) {
        $c = @($f.geometry.coordinates)
        if ($f.type -cne 'Feature' -or $f.geometry.type -cne 'Point' -or $c.Count -ne 2) { throw 'Geometria invalida.' }
        foreach ($v in $c) {
            if ($v -is [string] -or $v -is [bool] -or $null -eq $v -or [double]::IsNaN([double]$v) -or [double]::IsInfinity([double]$v)) { throw 'Coordenada invalida.' }
        }
        if ([math]::Abs([double]$c[0]) -gt 180 -or [math]::Abs([double]$c[1]) -gt 90) { throw 'Coordenada fora dos limites.' }
    }
    return $j
}
function Canonical($Json) {
    $Json.PSObject.Properties.Remove('generated_at')
    return ($Json | ConvertTo-Json -Depth 100 -Compress)
}
function GenerationTime($Json) {
    if (-not $Json.generated_at) { throw 'generated_at ausente.' }
    $stamp = [string]$Json.generated_at -replace '([+-]\d{2})(\d{2})$', '$1:$2'
    return [DateTimeOffset]::Parse($stamp, [Globalization.CultureInfo]::InvariantCulture)
}
function Git {
    param([Parameter(Mandatory = $true)][string[]]$GitArgs)
    $oldPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $result = & $script:GitExe @GitArgs 2>&1
    $code = $LASTEXITCODE
    $ErrorActionPreference = $oldPreference
    if ($code -ne 0) { throw ('Git falhou: ' + ($result -join [Environment]::NewLine)) }
    return ($result -join [Environment]::NewLine)
}
$lock = $null
try {
    $bytes = [IO.File]::ReadAllBytes($Source)
    Start-Sleep -Milliseconds 250
    $second = [IO.File]::ReadAllBytes($Source)
    if ([Convert]::ToBase64String($bytes) -cne [Convert]::ToBase64String($second)) { throw 'Arquivo sendo atualizado; nova tentativa no proximo agendamento.' }
    $text = [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF)
    $local = Read-GeoJson $text
    $localTime = GenerationTime $local
    $localCanonical = Canonical $local
    $riskText = $null
    if ($JsonSource) {
        $riskText = [IO.File]::ReadAllText($JsonSource, [Text.Encoding]::UTF8)
        $risk = $riskText | ConvertFrom-Json
        if ($risk.versao -ne 1 -or @($risk.janelas).Count -ne 3 -or
            [int]$risk.quantidade -ne @($local.features).Count) {
            throw 'JSON de 72 h incompatível com o GeoJSON.'
        }
        foreach ($window in $risk.janelas) {
            if (@($window.paineis).Count -ne [int]$risk.quantidade) {
                throw 'Janela de 72 h incompleta.'
            }
        }
    }
    if ($ValidateOnly) { Write-Output ('VALIDO: {0} pontos; geracao {1:o}' -f @($local.features).Count, $localTime); exit 0 }
    New-Item -ItemType Directory -Path $WorkingDirectory -Force | Out-Null
    $WorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory).Path
    $lock = [IO.File]::Open((Join-Path $WorkingDirectory 'sync.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
    $script:GitExe = (Get-Command git.exe -ErrorAction SilentlyContinue).Source
    if (-not $script:GitExe) { $script:GitExe = 'C:\Program Files\Git\cmd\git.exe' }
    if (-not $Interactive) { $env:GIT_TERMINAL_PROMPT = '0'; $env:GCM_INTERACTIVE = 'Never' }
    $repo = Join-Path $WorkingDirectory 'repo'
    if (-not (Test-Path -LiteralPath (Join-Path $repo '.git'))) {
        Git -GitArgs @('clone', '--branch', 'main', '--single-branch', 'https://github.com/dougease/nicky-windy-public.git', $repo) | Out-Null
    }
    $origin = Git -GitArgs @('-C', $repo, 'remote', 'get-url', 'origin')
    if ($origin.Trim() -cne 'https://github.com/dougease/nicky-windy-public.git') { throw 'Repositorio de destino inesperado.' }
    Git -GitArgs @('-C', $repo, 'fetch', 'origin', 'main') | Out-Null
    $remoteRiskText = $null
    if ($JsonSource) {
        $remoteRiskText = Git -GitArgs @('-C', $repo, 'show', 'origin/main:docs/windy/risco_72h.json')
    }
    $remoteText = Git -GitArgs @('-C', $repo, 'show', 'origin/main:paineis_nicky.geojson')
    $remote = Read-GeoJson $remoteText
    $remoteTime = GenerationTime $remote
    if ($localTime -lt $remoteTime) { throw 'Versao local mais antiga; publicacao cancelada.' }
    if ($localCanonical -ceq (Canonical $remote) -and
        (-not $JsonSource -or $riskText.Trim() -ceq $remoteRiskText.Trim())) {
        if ($Interactive) {
            # Confirma permissao de escrita, mesmo sem dados novos.
            Git -GitArgs @('-C', $repo, 'push', '--dry-run', 'origin', 'refs/remotes/origin/main:refs/heads/main') | Out-Null
            Write-Output 'Sem mudancas. Autenticacao de escrita verificada.'
        }
        exit 0
    }
    # Checkout exclusivo da automacao; nao altera o projeto Shiny.
    if (Git -GitArgs @('-C', $repo, 'status', '--porcelain')) { throw 'Checkout de publicacao contem alteracoes locais; verificar antes de continuar.' }
    Git -GitArgs @('-C', $repo, 'checkout', '--detach', 'origin/main') | Out-Null
    [IO.File]::WriteAllText((Join-Path $repo 'paineis_nicky.geojson'), $text, (New-Object Text.UTF8Encoding $false))
    Git -GitArgs @('-C', $repo, 'add', '--', 'paineis_nicky.geojson') | Out-Null
    if ($JsonSource) {
        $riskPath = Join-Path $repo 'docs\windy\risco_72h.json'
        [IO.File]::WriteAllText($riskPath, $riskText, (New-Object Text.UTF8Encoding $false))
        Git -GitArgs @('-C', $repo, 'add', '--', 'docs/windy/risco_72h.json') | Out-Null
    }
    Git -GitArgs @('-C', $repo, '-c', 'user.name=Nicky Windy Local', '-c', 'user.email=175320214+dougease@users.noreply.github.com', 'commit', '-m', ('Atualiza paineis Nicky: ' + $localTime.ToString('o'))) | Out-Null
    Git -GitArgs @('-C', $repo, 'push', 'origin', 'HEAD:refs/heads/main') | Out-Null
    Git -GitArgs @('-C', $repo, 'fetch', 'origin', 'main') | Out-Null
    $verified = Read-GeoJson (Git -GitArgs @('-C', $repo, 'show', 'origin/main:paineis_nicky.geojson'))
    if ((Canonical $verified) -cne $localCanonical) { throw 'Publicacao ainda nao confirmada.' }
    if ($JsonSource) {
        $verifiedRisk = Git -GitArgs @('-C', $repo, 'show', 'origin/main:docs/windy/risco_72h.json')
        if ($verifiedRisk.Trim() -cne $riskText.Trim()) { throw 'JSON de 72 h ainda nao confirmado.' }
    }
    $message = '{0:o} Publicados {1} pontos.' -f [DateTimeOffset]::Now, @($local.features).Count
    Add-Content -LiteralPath (Join-Path $WorkingDirectory 'sincronizacao.log') -Value $message -Encoding UTF8
    Write-Output $message
} catch {
    $message = '{0:o} ERRO: {1}' -f [DateTimeOffset]::Now, $_.Exception.Message
    if (-not $ValidateOnly -and (Test-Path -LiteralPath $WorkingDirectory)) {
        Add-Content -LiteralPath (Join-Path $WorkingDirectory 'sincronizacao.log') -Value $message -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    Write-Error $message -ErrorAction Continue
    exit 1
} finally {
    if ($lock) { $lock.Dispose() }
}
