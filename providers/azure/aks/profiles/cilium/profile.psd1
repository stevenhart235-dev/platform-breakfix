@{
    SchemaVersion = 1
    Name = 'cilium'
    Provider = 'aks'
    InfrastructureInputs = @{
        NetworkDataPlane = 'cilium'
        NodeVmSize = 'Standard_D2as_v7'
        NodeCount = 1
        ServiceMeshMode = 'Disabled'
        IstioRevision = ''
    }
    BootstrapComposition = 'kubernetes'
    ValidationScript = 'Validate-Cilium.ps1'
}
