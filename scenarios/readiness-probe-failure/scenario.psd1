@{
    SchemaVersion = 1
    Name = 'readiness-probe-failure'
    SupportedProviders = @('aks')
    SupportedProfiles = @('minimal')
    Description = 'Proves and repairs a readiness probe failure while the destination container remains Running.'
    KubernetesComposition = 'kubernetes'
    Hooks = @{
        Inject = 'Inject.ps1'
        ValidateBroken = 'Validate-Broken.ps1'
        Inspect = 'Inspect.ps1'
        Repair = 'Repair.ps1'
        ValidateRecovered = 'Validate-Recovered.ps1'
        Cleanup = 'Cleanup.ps1'
    }
}
