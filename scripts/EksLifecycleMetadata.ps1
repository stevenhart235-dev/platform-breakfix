Set-StrictMode -Version Latest

function Assert-ExactProperties {
    param([Parameter(Mandatory)] $Value, [Parameter(Mandatory)][string[]] $Expected, [string] $Context)
    $actual = @($Value.PSObject.Properties.Name)
    $missing = @($Expected | Where-Object { $_ -cnotin $actual })
    $extra = @($actual | Where-Object { $_ -cnotin $Expected })
    if ($missing.Count -or $extra.Count) {
        throw "$Context has an invalid field set. Missing=[$($missing -join ',')]; Extra=[$($extra -join ',')]."
    }
}

function Assert-EksLifecycleMetadata {
    param([Parameter(Mandatory)] $Metadata)
    $fields = @('SchemaVersion', 'LabId', 'AccountId', 'Region', 'CreatedAt', 'ExpiresAt')
    Assert-ExactProperties -Value $Metadata -Expected $fields -Context 'EKS lifecycle metadata'
    if ($Metadata.SchemaVersion -isnot [ValueType] -or [decimal]$Metadata.SchemaVersion -ne 1) { throw 'EKS lifecycle metadata SchemaVersion must be integer 1.' }
    $labId = [string]$Metadata.LabId
    $parsedLabId = [guid]::Empty
    if (-not [guid]::TryParseExact($labId, 'D', [ref]$parsedLabId) -or $labId -cne $parsedLabId.ToString('D')) { throw 'EKS lifecycle metadata LabId must be a canonical lowercase UUID.' }
    if ([string]$Metadata.AccountId -cnotmatch '^\d{12}$') { throw 'EKS lifecycle metadata AccountId must be a 12-digit AWS account ID.' }
    if ([string]$Metadata.Region -cnotmatch '^[a-z]{2}(-[a-z]+)+-\d+$') { throw 'EKS lifecycle metadata Region is invalid.' }
    $createdText = [string]$Metadata.CreatedAt
    $expiresText = [string]$Metadata.ExpiresAt
    if ($createdText -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or $expiresText -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$') { throw 'EKS lifecycle timestamps must use second-precision UTC RFC3339.' }
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    $created = [datetimeoffset]::ParseExact($createdText, 'yyyy-MM-ddTHH:mm:ssZ', $culture, $styles)
    $expires = [datetimeoffset]::ParseExact($expiresText, 'yyyy-MM-ddTHH:mm:ssZ', $culture, $styles)
    $duration = $expires - $created
    if ($duration.TotalHours -lt 1 -or $duration.TotalHours -gt 24 -or [math]::Floor($duration.TotalHours) -ne $duration.TotalHours) { throw 'EKS lifecycle ExpiresAt must be 1 through 24 whole hours after CreatedAt.' }
    return $Metadata
}

function Assert-EksLifecycleBinding {
    param(
        [Parameter(Mandatory)] $Metadata,
        [Parameter(Mandatory)][string] $AccountId,
        [Parameter(Mandatory)][string] $Region,
        [string] $LabId
    )
    Assert-EksLifecycleMetadata -Metadata $Metadata | Out-Null
    if ([string]$Metadata.AccountId -cne $AccountId) { throw 'Authenticated AWS account conflicts with the existing EKS lifecycle metadata.' }
    if ([string]$Metadata.Region -cne $Region) { throw 'Configured AWS region conflicts with the existing EKS lifecycle metadata.' }
    if ($PSBoundParameters.ContainsKey('LabId') -and [string]$Metadata.LabId -cne $LabId) { throw 'LabId conflicts with the existing EKS lifecycle metadata.' }
    return $Metadata
}