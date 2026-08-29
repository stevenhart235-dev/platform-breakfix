@{
    SchemaVersion = 1
    Name = 'istio'
    Provider = 'aks'
    InfrastructureInputs = @{
        NetworkDataPlane = 'azure'
        NodeVmSize = 'Standard_D4as_v7'
        NodeCount = 1
        ServiceMeshMode = 'Istio'
        IstioRevision = 'asm-1-30'
    }
    BootstrapComposition = 'kubernetes'
    ValidationScript = 'Validate-Istio.ps1'
}
