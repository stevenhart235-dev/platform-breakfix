[CmdletBinding()]
param(
    [ValidateRange(1, 65535)][int] $Port = $(if ($env:DASHBOARD_PORT) { [int]$env:DASHBOARD_PORT } else { 8080 }),
    [string] $BindAddress = '+',
    [ValidateSet('', 'healthy', 'readiness-degraded', 'selector-degraded', 'unknown')]
    [string] $Fixture = $(if ($env:LAB_HEALTH_FIXTURE) { $env:LAB_HEALTH_FIXTURE } else { '' }),
    [ValidateSet('minimal', 'cilium', 'istio')]
    [string] $Profile = $(if ($env:LAB_HEALTH_PROFILE) { $env:LAB_HEALTH_PROFILE } else { 'minimal' }),
    [switch] $SimulateCollectorFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $repositoryRoot 'scripts/LabHealth.ps1')

$fixturePaths = @{
    healthy              = 'dashboard/fixtures/healthy.json'
    'readiness-degraded' = 'dashboard/fixtures/readiness-degraded.json'
    'selector-degraded'  = 'dashboard/fixtures/selector-degraded.json'
    unknown              = 'dashboard/fixtures/unknown.json'
}
$componentNames = @('Nodes', 'Pods', 'PVCs', 'Services', 'Endpoints', 'Cilium', 'Istio')

function Get-CurrentLabHealth {
    if ($SimulateCollectorFailure) { throw 'Simulated health collector failure.' }
    if ($Fixture) {
        return Read-LabHealthContract (Join-Path $repositoryRoot $fixturePaths[$Fixture])
    }
    Get-AksLabHealth -Profile $Profile
}

function ConvertTo-HtmlText([AllowNull()] $Value) {
    [Net.WebUtility]::HtmlEncode([string]$Value)
}

function Get-DashboardHtml {
    param([AllowNull()] $Health, [bool] $Available)
    $template = Get-Content -Raw (Join-Path $PSScriptRoot 'static/index.html')
    $overall = if ($Available) { $Health.Overall } else { 'UNKNOWN' }
    $observed = if ($Available) { $Health.ObservedAt } else { 'Unavailable' }
    $bannerClass = if ($Available) { 'availability hidden' } else { 'availability' }
    $bannerText = if ($Available) { '' } else { 'Current health is unavailable. No stale observation is presented as current.' }
    $rows = foreach ($name in $componentNames) {
        $component = if ($Available) { $Health.Components.$name } else { $null }
        $status = if ($Available) { $component.Status } else { 'UNKNOWN' }
        $summary = if ($Available) { $component.Summary } else { 'Current health unavailable.' }
        $version = if ($Available -and $component.PSObject.Properties.Name -contains 'Version' -and $component.Version) { '<span class="version">Version: {0}</span>' -f (ConvertTo-HtmlText $component.Version) } else { '' }
        '<article class="component state-{0}" id="component-{1}"><h3>{2}</h3><strong class="status" id="{1}-status">{3}</strong><p id="{1}-summary">{4}</p>{5}</article>' -f $status.ToLowerInvariant().Replace('_','-'), $name.ToLowerInvariant(), (ConvertTo-HtmlText $name), (ConvertTo-HtmlText $status), (ConvertTo-HtmlText $summary), $version
    }
    $template.Replace('{{OVERALL}}', (ConvertTo-HtmlText $overall)).Replace('{{OBSERVED_AT}}', (ConvertTo-HtmlText $observed)).Replace('{{BANNER_CLASS}}', $bannerClass).Replace('{{BANNER_TEXT}}', (ConvertTo-HtmlText $bannerText)).Replace('{{COMPONENTS}}', ($rows -join "`n"))
}

function Write-Response {
    param($Context, [int] $StatusCode, [string] $ContentType, [string] $Body)
    $bytes = [Text.Encoding]::UTF8.GetBytes($Body)
    $Context.Response.StatusCode = $StatusCode
    $Context.Response.ContentType = "$ContentType; charset=utf-8"
    $Context.Response.ContentLength64 = $bytes.Length
    $Context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
    $Context.Response.Close()
}

function Write-Unavailable($Context) {
    Write-Response $Context 503 'application/json' '{"Error":{"Code":"HEALTH_UNAVAILABLE","Message":"Current lab health is unavailable."}}'
}

$listener = [Net.HttpListener]::new()
$listener.Prefixes.Add("http://${BindAddress}:$Port/")
$listener.Start()
Write-Host "Lab Health Dashboard listening on port $Port."
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        try {
            if ($context.Request.HttpMethod -cne 'GET') {
                Write-Response $context 405 'application/json' '{"Error":{"Code":"METHOD_NOT_ALLOWED","Message":"Only GET is supported."}}'
                continue
            }
            switch ($context.Request.Url.AbsolutePath) {
                '/healthz' { Write-Response $context 200 'application/json' '{"Status":"OK"}' }
                '/api/health' {
                    try { Write-Response $context 200 'application/json' (ConvertTo-LabHealthJson (Get-CurrentLabHealth)) }
                    catch { Write-Unavailable $context }
                }
                '/' {
                    try { Write-Response $context 200 'text/html' (Get-DashboardHtml (Get-CurrentLabHealth) $true) }
                    catch { Write-Response $context 200 'text/html' (Get-DashboardHtml $null $false) }
                }
                '/app.js' { Write-Response $context 200 'text/javascript' (Get-Content -Raw (Join-Path $PSScriptRoot 'static/app.js')) }
                '/styles.css' { Write-Response $context 200 'text/css' (Get-Content -Raw (Join-Path $PSScriptRoot 'static/styles.css')) }
                default { Write-Response $context 404 'application/json' '{"Error":{"Code":"NOT_FOUND","Message":"Resource not found."}}' }
            }
        }
        catch {
            if ($context.Response.OutputStream.CanWrite) { Write-Response $context 500 'application/json' '{"Error":{"Code":"INTERNAL_ERROR","Message":"Request failed."}}' }
        }
    }
}
finally {
    $listener.Stop()
    $listener.Close()
}
