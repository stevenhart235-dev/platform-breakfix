Set-StrictMode -Version Latest

function Get-BreakfixHumanLines {
    param([Parameter(Mandatory)] $Result)
    if (-not $Result.Success) { return @() }
    switch ($Result.Operation) {
        'list_profiles' { return @($Result.Data.Profiles | ForEach-Object { "{0,-12} {1}" -f $_.Name, $_.Provider }) }
        'list_scenarios' { return @($Result.Data.Scenarios | ForEach-Object { "{0} - {1}" -f $_.Name, $_.Description }) }
        'read_evidence' { return @("Scenario:  $($Result.Data.Scenario)", "Provider:  $($Result.Data.Provider)", "Profile:   $($Result.Data.Profile)", "Status:    $($Result.Data.Status)", "Diagnosis: $($Result.Data.Diagnosis.Identifier)") }
        'diagnose_evidence' { return @("Diagnosis: $($Result.Data.Identifier)", "Summary:   $($Result.Data.Summary)") }
        'get_lab_status' {
            return @(
                "Provider:   $($Result.Data.Provider)",
                "State:      $($Result.Data.State)",
                "Profile:    $(if ($Result.Data.Profile) { $Result.Data.Profile } else { '-' })",
                "Created:    $(if ($Result.Data.CreatedAt) { $Result.Data.CreatedAt } else { '-' })",
                "Expires:    $(if ($Result.Data.ExpiresAt) { $Result.Data.ExpiresAt } else { '-' })",
                "Connection: $($Result.Data.ConnectionState)"
            )
        }
        'get_lab_health' {
            $lines = @("Lab Health: $($Result.Data.Overall)", '')
            foreach ($name in @('Nodes', 'Pods', 'PVCs', 'Services', 'Endpoints', 'Cilium', 'Istio')) {
                $lines += '{0,-11} {1}' -f $name, $Result.Data.Components.$name.Status
            }
            return $lines
        }
    }
    @()
}

function Invoke-BreakfixCliAdapter {
    param(
        [AllowEmptyString()][string] $Resource,
        [AllowEmptyString()][string] $Action,
        [AllowEmptyString()][string] $Identifier,
        [AllowEmptyString()][string] $Provider,
        [bool] $Json,
        [Parameter(Mandatory)][scriptblock] $OperationInvoker
    )
    $operation = $null
    $arguments = @{}
    $contractVersion = 1
    if ($Resource -ceq 'profiles' -and $Action -ceq 'list' -and -not $Identifier) {
        $operation = 'list_profiles'; if ($Provider) { $arguments.Provider = $Provider }
    }
    elseif ($Resource -ceq 'scenarios' -and $Action -ceq 'list' -and -not $Identifier -and -not $Provider) { $operation = 'list_scenarios' }
    elseif ($Resource -ceq 'evidence' -and $Action -ceq 'read' -and $Identifier -and -not $Provider) { $operation = 'read_evidence'; $arguments.Scenario = $Identifier }
    elseif ($Resource -ceq 'evidence' -and $Action -ceq 'diagnose' -and $Identifier -and -not $Provider) { $operation = 'diagnose_evidence'; $arguments.Scenario = $Identifier }
    elseif ($Resource -ceq 'lab' -and $Action -ceq 'status' -and -not $Identifier -and $Provider) { $operation = 'get_lab_status'; $arguments.Provider = $Provider }
    elseif ($Resource -ceq 'lab' -and $Action -ceq 'health' -and -not $Identifier -and $Provider) { $operation = 'get_lab_health'; $arguments.Provider = $Provider; $contractVersion = 2 }

    if (-not $operation) {
        $version = if ($Resource -ceq 'lab' -and $Action -ceq 'health') { 2 } else { 1 }
        $failure = [pscustomobject][ordered]@{
            ContractVersion = $version; Operation = 'invalid_cli_command'; Success = $false; Data = $null
            Error = [pscustomobject][ordered]@{ Code = 'INVALID_ARGUMENT'; Message = 'Usage: breakfix.ps1 profiles list [-Provider aks] [-Json] | scenarios list [-Json] | evidence read|diagnose <scenario> [-Json] | lab status|health -Provider <provider> [-Json]' }
        }
        return [pscustomobject]@{ ExitCode = 2; StandardOutput = $(if ($Json) { @($failure | ConvertTo-Json -Depth 10 -Compress) } else { @() }); StandardError = $(if ($Json) { @() } else { @("$($failure.Error.Code): $($failure.Error.Message)") }) }
    }

    $result = & $OperationInvoker $operation $arguments $contractVersion
    if ($Json) { $stdout = @($result | ConvertTo-Json -Depth 10 -Compress); $stderr = @() }
    elseif ($result.Success) { $stdout = @(Get-BreakfixHumanLines $result); $stderr = @() }
    else { $stdout = @(); $stderr = @("$($result.Error.Code): $($result.Error.Message)") }
    [pscustomobject]@{ ExitCode = $(if ($result.Success) { 0 } else { 1 }); StandardOutput = $stdout; StandardError = $stderr }
}
