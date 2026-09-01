[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Position = 0)][string] $Resource,
    [Parameter(Position = 1)][string] $Action,
    [Parameter(Position = 2)][string] $Identifier,
    [string] $Provider,
    [switch] $Json
)

$ErrorActionPreference = 'Stop'
$repositoryRoot = $PSScriptRoot
. (Join-Path $repositoryRoot 'scripts/BreakfixOperations.ps1')
. (Join-Path $repositoryRoot 'scripts/BreakfixCli.ps1')
$invokeOperation = { param($Operation, $Arguments, $ContractVersion) Invoke-BreakfixOperation -Operation $Operation -Arguments $Arguments -ContractVersion $ContractVersion }
$response = Invoke-BreakfixCliAdapter -Resource $Resource -Action $Action -Identifier $Identifier -Provider $Provider -Json $Json.IsPresent -OperationInvoker $invokeOperation
foreach ($line in @($response.StandardOutput)) { Write-Output $line }
foreach ($line in @($response.StandardError)) { [Console]::Error.WriteLine($line) }
exit $response.ExitCode
