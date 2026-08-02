# Claude Code status line: model name + context window usage.
# PowerShell port of the host's bash/python version - the sandbox has neither
# bash nor python guaranteed, but always has powershell.exe.
$ErrorActionPreference = 'Stop'
try {
    $data  = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $model = if ($data.model.display_name) { $data.model.display_name } else { 'Claude' }
    $used  = $data.context_window.used_percentage
    if ($null -ne $used) {
        '{0} | Context: {1:N0}% used' -f $model, $used
    } else {
        $model
    }
} catch {
    'Claude'
}
