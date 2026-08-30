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

function Write-BreakfixHumanResult {
    param([Parameter(Mandatory)] $Result)
    if (-not $Result.Success) {
        [Console]::Error.WriteLine("$($Result.Error.Code): $($Result.Error.Message)")
        return
    }
    switch ($Result.Operation) {
        'list_profiles' {
            foreach ($profile in @($Result.Data.Profiles)) { Write-Output ("{0,-12} {1}" -f $profile.Name, $profile.Provider) }
        }
        'list_scenarios' {
            foreach ($scenario in @($Result.Data.Scenarios)) { Write-Output ("{0} - {1}" -f $scenario.Name, $scenario.Description) }
        }
        'read_evidence' {
            Write-Output ("Scenario:  {0}" -f $Result.Data.Scenario)
            Write-Output ("Provider:  {0}" -f $Result.Data.Provider)
            Write-Output ("Profile:   {0}" -f $Result.Data.Profile)
            Write-Output ("Status:    {0}" -f $Result.Data.Status)
            Write-Output ("Diagnosis: {0}" -f $Result.Data.Diagnosis.Identifier)
        }
        'diagnose_evidence' {
            Write-Output ("Diagnosis: {0}" -f $Result.Data.Identifier)
            Write-Output ("Summary:   {0}" -f $Result.Data.Summary)
        }
        'get_lab_status' {
            Write-Output ("Provider:   {0}" -f $Result.Data.Provider)
            Write-Output ("State:      {0}" -f $Result.Data.State)
            Write-Output ("Profile:    {0}" -f $(if ($Result.Data.Profile) { $Result.Data.Profile } else { '-' }))
            Write-Output ("Created:    {0}" -f $(if ($Result.Data.CreatedAt) { $Result.Data.CreatedAt } else { '-' }))
            Write-Output ("Expires:    {0}" -f $(if ($Result.Data.ExpiresAt) { $Result.Data.ExpiresAt } else { '-' }))
            Write-Output ("Connection: {0}" -f $Result.Data.ConnectionState)
        }
    }
}

$operation = $null
$arguments = @{}
if ($Resource -ceq 'profiles' -and $Action -ceq 'list' -and -not $Identifier) {
    $operation = 'list_profiles'
    if ($Provider) { $arguments.Provider = $Provider }
}
elseif ($Resource -ceq 'scenarios' -and $Action -ceq 'list' -and -not $Identifier -and -not $Provider) {
    $operation = 'list_scenarios'
}
elseif ($Resource -ceq 'evidence' -and $Action -ceq 'read' -and $Identifier -and -not $Provider) {
    $operation = 'read_evidence'; $arguments.Scenario = $Identifier
}
elseif ($Resource -ceq 'evidence' -and $Action -ceq 'diagnose' -and $Identifier -and -not $Provider) {
    $operation = 'diagnose_evidence'; $arguments.Scenario = $Identifier
}
elseif ($Resource -ceq 'lab' -and $Action -ceq 'status' -and -not $Identifier -and $Provider) {
    $operation = 'get_lab_status'; $arguments.Provider = $Provider
}

if (-not $operation) {
    $failure = [pscustomobject][ordered]@{
        ContractVersion = 1; Operation = 'invalid_cli_command'; Success = $false; Data = $null
        Error = [pscustomobject][ordered]@{ Code = 'INVALID_ARGUMENT'; Message = 'Usage: breakfix.ps1 profiles list [-Provider aks] [-Json] | scenarios list [-Json] | evidence read|diagnose <scenario> [-Json] | lab status -Provider <provider> [-Json]' }
    }
    if ($Json) { $failure | ConvertTo-Json -Depth 10 -Compress } else { [Console]::Error.WriteLine("$($failure.Error.Code): $($failure.Error.Message)") }
    exit 2
}

$result = Invoke-BreakfixOperation -Operation $operation -Arguments $arguments
if ($Json) { $result | ConvertTo-Json -Depth 10 -Compress } else { Write-BreakfixHumanResult $result }
if ($result.Success) { exit 0 }
exit 1
