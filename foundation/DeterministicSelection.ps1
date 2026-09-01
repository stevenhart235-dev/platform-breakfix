Set-StrictMode -Version Latest

function Resolve-DeterministicSelection {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Candidates)

    $validated = foreach ($candidate in $Candidates) {
        if ($null -eq $candidate) { throw 'Deterministic selection candidate must not be null.' }
        $fields = @($candidate.psobject.Properties.Name)
        $required = @('Name', 'Matches', 'Value')
        if (@($required | Where-Object { $_ -notin $fields }).Count -or @($fields | Where-Object { $_ -notin $required }).Count) {
            throw 'Deterministic selection candidate has an invalid shape.'
        }
        if ($candidate.Name -isnot [string] -or [string]::IsNullOrWhiteSpace($candidate.Name)) { throw 'Deterministic selection candidate Name must be a non-empty string.' }
        if ($candidate.Matches -isnot [bool]) { throw 'Deterministic selection candidate Matches must be boolean.' }
        if ($null -eq $candidate.Value) { throw 'Deterministic selection candidate Value must not be null.' }
        $candidate
    }
    $names = @($validated | ForEach-Object Name)
    if (@($names | Sort-Object -Unique).Count -ne $names.Count) { throw 'Deterministic selection candidate names must be unique.' }
    $matches = @($validated | Where-Object Matches | Sort-Object Name)
    if ($matches.Count -ne 1) { throw "Deterministic selection requires exactly one match; found $($matches.Count)." }
    $matches[0].Value
}
