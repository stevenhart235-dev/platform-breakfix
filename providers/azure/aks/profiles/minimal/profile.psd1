@{
    SchemaVersion = 1
    Name = 'minimal'
    Provider = 'aks'
    InfrastructureInputs = @{
        NetworkDataPlane = 'azure'
        NodeVmSize = 'Standard_D2as_v7'
        NodeCount = 1
    }
    BootstrapComposition = 'kubernetes'
    ValidationScript = $null
}
