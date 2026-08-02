@{
    RootModule        = 'Corral.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'd7f3a1c2-4e6b-4a58-9c0d-2b8e5f1a7c34'
    Author            = 'Fleibian'
    Description       = 'Single entry point for the agent workspace: isolated, disposable WSL2 development environments for AI coding agents.'
    PowerShellVersion = '7.0'

    FunctionsToExport = @('Invoke-Corral')
    AliasesToExport   = @('corral')
    CmdletsToExport   = @()
    VariablesToExport = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('wsl', 'agents', 'sandbox', 'development')
            ProjectUri = 'https://github.com/Fleibian/corral'
        }
    }
}
