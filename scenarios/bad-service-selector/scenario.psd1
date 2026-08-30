@{
    SchemaVersion = 1
    Name = 'bad-service-selector'
    SupportedProviders = @('aks')
    SupportedProfiles = @('minimal')
    Description = 'Proves and repairs a Service selector mismatch while DNS and both workloads remain healthy.'
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
