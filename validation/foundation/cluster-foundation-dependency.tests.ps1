[CmdletBinding()] param()
$ErrorActionPreference = 'Stop'
$RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$submodulePath = Join-Path $RepositoryRoot 'external/cluster-foundation'
$lockPath = Join-Path $RepositoryRoot 'external/cluster-foundation.lock.json'
$approvedUrl = 'https://github.com/stevenhart235-dev/cluster-foundation.git'
$approvedSha = '06509854104d8b0289790a6ec3b3bd9053761522'
$approvedSourceSha = 'F03C4401552FB6F9F9BE65DB813127B8ECF020A1089A8889064F95C4A0B4D866'
function Assert-True([bool]$Condition,[string]$Message){if(-not$Condition){throw $Message}}
function Invoke-Git([string[]]$Arguments,[string]$WorkingDirectory=$RepositoryRoot){$output=&git -C $WorkingDirectory @Arguments 2>&1;if($LASTEXITCODE-ne0){throw "git $($Arguments-join' ') failed: $($output-join[Environment]::NewLine)"};[string]($output-join[Environment]::NewLine)}
function Get-GitBlobSha256([string]$Repository,[string]$Revision,[string]$Path){
    $start=[Diagnostics.ProcessStartInfo]::new('git');$start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    foreach($argument in @('-C',$Repository,'cat-file','blob',"${Revision}:$Path")){[void]$start.ArgumentList.Add($argument)}
    $process=[Diagnostics.Process]::Start($start);$memory=[IO.MemoryStream]::new();$process.StandardOutput.BaseStream.CopyTo($memory);$errorText=$process.StandardError.ReadToEnd();$process.WaitForExit()
    if($process.ExitCode-ne0){throw "Could not read locked Git blob: $errorText"}
    try{[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($memory.ToArray()))}finally{$memory.Dispose();$process.Dispose()}
}
Assert-True (Test-Path -LiteralPath $submodulePath -PathType Container) 'Required cluster-foundation submodule is absent. Run: git submodule update --init --recursive'
Assert-True (Test-Path -LiteralPath $lockPath -PathType Leaf) 'Foundation dependency lock is absent.'
$lock=Get-Content -Raw -LiteralPath $lockPath|ConvertFrom-Json
$required=@('SchemaVersion','Name','RepositoryUrl','Version','Tag','CommitSha','SourcePath','SourceSha256','ContractMajorVersion');$fields=@($lock.psobject.Properties.Name)
Assert-True (@(Compare-Object ($required|Sort-Object) ($fields|Sort-Object)).Count-eq0) 'Foundation lock shape is invalid.'
Assert-True ($lock.SchemaVersion-eq1-and$lock.Name-ceq'cluster-foundation'-and$lock.RepositoryUrl-ceq$approvedUrl) 'Foundation lock identity is invalid.'
Assert-True ($lock.Version-ceq'0.1.0'-and$lock.Tag-ceq'v0.1.0'-and$lock.CommitSha-ceq$approvedSha-and$lock.ContractMajorVersion-eq0) 'Foundation lock version, tag, commit, or contract major is invalid.'
Assert-True ($lock.SourcePath-ceq'src/DeterministicSelection.ps1'-and$lock.SourceSha256-ceq$approvedSourceSha) 'Foundation lock source identity is invalid.'
$moduleUrl=(Invoke-Git @('config','-f','.gitmodules','--get','submodule.external/cluster-foundation.url')).Trim();$moduleBranch=&git -C $RepositoryRoot config -f .gitmodules --get submodule.external/cluster-foundation.branch 2>$null
Assert-True ($moduleUrl-ceq$approvedUrl-and-not$moduleBranch) '.gitmodules URL is unapproved or a mutable branch is configured.'
$stage=Invoke-Git @('ls-files','--stage','--','external/cluster-foundation')
Assert-True ($stage-match'^160000 ([0-9a-f]{40}) 0\s+external/cluster-foundation$') 'Foundation dependency is not a gitlink.';$gitlink=$Matches[1]
$head=(Invoke-Git @('rev-parse','HEAD') $submodulePath).Trim();$origin=(Invoke-Git @('remote','get-url','origin') $submodulePath).Trim()
Assert-True ($gitlink-ceq$approvedSha-and$head-ceq$approvedSha-and$lock.CommitSha-ceq$gitlink) 'Gitlink, submodule HEAD, and lock SHA disagree.'
Assert-True ($origin-ceq$approvedUrl) 'Initialized submodule remote URL is unapproved.'
$symbolic=&git -C $submodulePath symbolic-ref -q HEAD 2>$null;Assert-True ($LASTEXITCODE-ne0-and-not$symbolic) 'Foundation dependency is attached to a mutable branch.'
$version=(Get-Content -Raw -LiteralPath (Join-Path $submodulePath 'VERSION')).Trim();Assert-True ($version-ceq$lock.Version) 'Foundation VERSION disagrees with the lock.'
$sourcePath=Join-Path $submodulePath $lock.SourcePath;Assert-True (Test-Path -LiteralPath $sourcePath -PathType Leaf) 'Locked foundation source is absent.'
$sourceSha=Get-GitBlobSha256 -Repository $submodulePath -Revision $approvedSha -Path $lock.SourcePath;Assert-True ($sourceSha-ceq$approvedSourceSha) 'Foundation Git blob SHA-256 disagrees with the lock.'
$tagTarget=(Invoke-Git @('rev-list','-n','1',$lock.Tag) $submodulePath).Trim();Assert-True ($tagTarget-ceq$approvedSha) 'Foundation release tag does not resolve to the pinned commit.'
$allowedSigners=&git config --get gpg.ssh.allowedSignersFile 2>$null
if($LASTEXITCODE-eq0-and-not[string]::IsNullOrWhiteSpace(($allowedSigners-join''))){Invoke-Git @('tag','-v',$lock.Tag) $submodulePath|Out-Null;Write-Host 'PASS: foundation tag signature verified.' -ForegroundColor Green}else{Write-Warning 'Git SSH allowed signers are unavailable; tag signature verification was not executable in this environment.'}
$t=$null;$parseErrors=$null;[void][Management.Automation.Language.Parser]::ParseFile($sourcePath,[ref]$t,[ref]$parseErrors);Assert-True (@($parseErrors).Count-eq0) 'Pinned foundation source does not parse.'
$scenarioSource=Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'scripts/ScenarioDiagnosis.ps1');$aksSource=Get-Content -Raw -LiteralPath (Join-Path $RepositoryRoot 'providers/azure/aks/scripts/Lab-Aks.ps1');$dependency='external/cluster-foundation/src/DeterministicSelection.ps1'
Assert-True ($scenarioSource-match[regex]::Escape($dependency)-and$aksSource-match[regex]::Escape($dependency)) 'Both consumers do not load the pinned foundation source.'
Assert-True (-not(Test-Path (Join-Path $RepositoryRoot 'foundation/DeterministicSelection.ps1'))) 'Tracked local deterministic-selection implementation remains.'
$implementations=@(Get-ChildItem (Join-Path $RepositoryRoot 'scripts'),(Join-Path $RepositoryRoot 'providers'),(Join-Path $submodulePath 'src') -Recurse -File -Filter '*.ps1'|Where-Object{(Get-Content -Raw $_.FullName)-match'function Resolve-DeterministicSelection'})
Assert-True ($implementations.Count-eq1-and$implementations[0].FullName-ceq$sourcePath) 'Exactly one reachable deterministic-selection implementation was not found.'
$guards=@(rg -l --glob '*.ps1' '\$matches\.Count -ne 1' (Join-Path $RepositoryRoot 'scripts') (Join-Path $RepositoryRoot 'providers') (Join-Path $submodulePath 'src'))
Assert-True ($guards.Count-eq1-and$guards[0]-match'external[\\/]cluster-foundation[\\/]src[\\/]DeterministicSelection\.ps1$') 'Consumer code duplicates generic exactly-one mechanics.'
$foundationExecutable=(Get-Content -Raw $sourcePath)+(Get-Content -Raw (Join-Path $submodulePath 'tests/DeterministicSelection.tests.ps1'))
Assert-True ($foundationExecutable-notmatch'platform-breakfix|ScenarioDiagnosis|Lab-Aks') 'Foundation depends on a platform consumer.'
Write-Host 'PASS: pinned cluster-foundation dependency integrity and architecture.' -ForegroundColor Green
