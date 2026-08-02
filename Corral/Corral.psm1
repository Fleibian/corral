<#
    corral - a single entry point for the agent workspace.

    A thin dispatcher over the scripts in the repository root. Those scripts
    remain the implementation and stay callable directly; this exists so the
    everyday commands are short, discoverable, and tab-complete project names
    instead of requiring you to remember and retype them.
#>

Set-StrictMode -Version Latest

# The module lives at <root>\Corral, so the workspace is one level up. Resolved
# rather than hardcoded, so the repo can be cloned or moved anywhere.
$script:Root = Split-Path -Parent $PSScriptRoot

# Reused for the argument completer, so the project list comes from the same
# place Get-Project.ps1 gets it rather than being derived a second way.
. (Join-Path $script:Root 'Common.ps1')

$script:Commands = [ordered]@{
    'new'   = @{ Script = 'New-Project.ps1';     Summary = 'Create a project and open it'; Usage = 'corral new <name>';                    Switches = @('-NoLaunch') }
    'open'  = @{ Script = 'Start-Project.ps1';   Summary = 'Open an existing project';     Usage = 'corral open <name>';                   Switches = @('-Shell', '-NoHerdr') }
    'ls'    = @{ Script = 'Get-Project.ps1';     Summary = 'List projects';                Usage = 'corral ls [-Detailed]';                Switches = @('-Detailed') }
    'rm'    = @{ Script = 'Remove-Project.ps1';  Summary = 'Destroy a project';            Usage = 'corral rm <name> [-NoBackup] [-Force]'; Switches = @('-NoBackup', '-Force', '-WhatIf') }
    'build' = @{ Script = 'Build-BaseImage.ps1'; Summary = 'Rebuild the base image';       Usage = 'corral build [-Force]';                Switches = @('-Force', '-KeepBuildDistro') }
    'help'  = @{ Script = $null;                 Summary = 'Show this help';               Usage = 'corral help';                          Switches = @() }
}

# Whatever you reach for first should work.
$script:Aliases = @{
    'create' = 'new';     'n'       = 'new'
    'start'  = 'open';    'o'       = 'open'
    'list'   = 'ls';      'l'       = 'ls'
    'remove' = 'rm';      'delete'  = 'rm';    'destroy' = 'rm'
    'rebuild'= 'build'
    '--help' = 'help';    '-h'      = 'help';  '-?'      = 'help'
}

# Subcommands that name an existing project, and so should complete one.
$script:TakesExistingName = @('open', 'rm')

function Resolve-CorralCommand {
    param([string]$Word)
    if (-not $Word) { return $null }
    $key = $Word.ToLowerInvariant()
    if ($script:Aliases.ContainsKey($key)) { $key = $script:Aliases[$key] }
    if ($script:Commands.Contains($key)) { return $key }
    return $null
}

function Get-CorralProjectName {
    <#
    .SYNOPSIS
        Project names, for tab completion.
    .DESCRIPTION
        Same filter Get-Project.ps1 applies: only distributions this tool owns,
        and never the transient base-image build distro.
    #>
    try {
        Get-WslDistro |
            Where-Object { $_.StartsWith($AgentDevPrefix) -and $_ -ne "${AgentDevPrefix}basebuild" } |
            ForEach-Object { $_.Substring($AgentDevPrefix.Length) }
    } catch {
        # Completion must never throw - a broken WSL just means no suggestions.
        @()
    }
}

function ConvertTo-CorralArguments {
    <#
    .SYNOPSIS
        Splits forwarded tokens into positional values and a splattable hashtable.
    .DESCRIPTION
        Array splatting passes every element positionally, so `-NoBackup` would
        arrive at the target script as the literal string "-NoBackup" and fail
        to bind. Only hashtable splatting binds named parameters, so switches
        and named values have to be separated out here.
    #>
    param([object[]]$Tokens)

    $positional = @()
    $named      = @{}

    # $Rest is $null when nothing was forwarded, and @($null) is a one-element
    # array holding null - which would otherwise be passed on as a positional
    # argument and rejected by the target script.
    $Tokens = @($Tokens | Where-Object { $null -ne $_ -and "$_" -ne '' })

    for ($i = 0; $i -lt $Tokens.Count; $i++) {
        $token = "$($Tokens[$i])"

        if (-not $token.StartsWith('-')) { $positional += $Tokens[$i]; continue }

        # -Switch:$false form, which PowerShell hands over as one token.
        if ($token -match '^-([^:]+):(.*)$') {
            $value = switch ($Matches[2]) {
                '$false' { $false }
                '$true'  { $true }
                'false'  { $false }
                'true'   { $true }
                default  { $Matches[2] }
            }
            $named[$Matches[1]] = $value
            continue
        }

        $name = $token.TrimStart('-')
        $next = if ($i + 1 -lt $Tokens.Count) { "$($Tokens[$i + 1])" } else { $null }

        if ($null -ne $next -and -not $next.StartsWith('-')) {
            $named[$name] = $Tokens[$i + 1]
            $i++
        } else {
            $named[$name] = [switch]$true
        }
    }

    [pscustomobject]@{ Positional = $positional; Named = $named }
}

function Show-CorralHelp {
    Write-Host ''
    Write-Host '  corral - isolated dev environments for coding agents' -ForegroundColor White
    Write-Host ''
    # Width derived from the longest usage string, so a new command can never
    # silently collide with its own summary.
    $width = ($script:Commands.Values | ForEach-Object { $_.Usage.Length } | Measure-Object -Maximum).Maximum + 2
    foreach ($name in $script:Commands.Keys) {
        Write-Host ("    {0,-$width}" -f $script:Commands[$name].Usage) -ForegroundColor Cyan -NoNewline
        Write-Host $script:Commands[$name].Summary -ForegroundColor Gray
    }
    Write-Host ''
    Write-Host '    Project names tab-complete: corral open <TAB>' -ForegroundColor DarkGray
    Write-Host ("    Scripts live in {0} and remain callable directly." -f $script:Root) -ForegroundColor DarkGray
    Write-Host ''
}

function Invoke-Corral {
    <#
    .SYNOPSIS
        Entry point for the agent workspace. Use the 'corral' alias.
    .EXAMPLE
        corral new invoice-service
    .EXAMPLE
        corral rm scratch -NoBackup -Force
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Command,

        [Parameter(Position = 1)]
        [string]$Name,

        # Everything else is forwarded, so switches behave exactly as they do
        # on the underlying script.
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$Rest
    )

    if (-not $Command) {
        & (Join-Path $script:Root 'Get-Project.ps1')
        Write-Host "  corral help  for the full command list" -ForegroundColor DarkGray
        Write-Host ''
        return
    }

    $key = Resolve-CorralCommand $Command
    if (-not $key) {
        Write-Host ''
        Write-Warning "Unknown command '$Command'."
        Show-CorralHelp
        return
    }

    if ($key -eq 'help') { Show-CorralHelp; return }

    $target = Join-Path $script:Root $script:Commands[$key].Script
    if (-not (Test-Path $target)) {
        throw "Missing script: $target. The Corral module expects to sit alongside it in the workspace root."
    }

    $parsed = ConvertTo-CorralArguments -Tokens @($Rest)
    $positional = @()
    if ($Name) { $positional += $Name }
    $positional += $parsed.Positional
    $named = $parsed.Named

    # -WhatIf and -Confirm are common parameters, so CmdletBinding swallows them
    # here rather than letting them fall through to $Rest. Forward them
    # explicitly - `corral rm x -WhatIf` is exactly when you want them.
    foreach ($common in 'WhatIf', 'Confirm') {
        if ($PSBoundParameters.ContainsKey($common)) { $named[$common] = $PSBoundParameters[$common] }
    }

    & $target @positional @named
}

$script:CorralCompleter = {
    param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

    # Driven from the AST rather than the bound parameter name. Because
    # Invoke-Corral has a ValueFromRemainingArguments parameter, PowerShell
    # cannot decide whether a positional token belongs to -Name or -Rest, and
    # silently falls back to filesystem completion - which is why this is
    # registered for every parameter and works out the position itself.
    $all = @()
    if ($commandAst) {
        $all = @($commandAst.CommandElements | Select-Object -Skip 1 | ForEach-Object { $_.Extent.Text })
    }
    $used   = @($all | Where-Object { $_.StartsWith('-') })
    $tokens = @($all | Where-Object { -not $_.StartsWith('-') })

    # A partially typed word is already in the token list; drop it so the index
    # reflects the slot being completed rather than the one after it. Uses
    # Select-Object rather than a range, because $tokens[0..-1] wraps around in
    # PowerShell and silently yields the wrong slice for a single token.
    if ($wordToComplete) {
        $tokens = @($tokens | Select-Object -First ([Math]::Max(0, $tokens.Count - 1)))
        $used   = @($used   | Select-Object -First ([Math]::Max(0, $used.Count   - 1)))
    }

    $verb = if ($tokens.Count -ge 1) { Resolve-CorralCommand $tokens[0] } else { $null }

    $candidates =
        if ($tokens.Count -eq 0) {
            @($script:Commands.Keys)
        } elseif (-not $verb) {
            @()
        } elseif ($tokens.Count -eq 1 -and $verb -in $script:TakesExistingName) {
            @(Get-CorralProjectName)
        } else {
            # No project name to offer here. Suggest the command's own switches
            # instead - useful in its own right, and it keeps PowerShell from
            # falling back to filesystem paths, which are never valid here.
            @($script:Commands[$verb].Switches | Where-Object { $_ -notin $used })
        }

    $candidates |
        Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object {
            $tip =
                if ($script:Commands.Contains($_)) { $script:Commands[$_].Summary }
                elseif ($_.StartsWith('-'))        { "switch $_" }
                else                               { "project '$_'" }
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $tip)
        }
}

foreach ($parameter in 'Command', 'Name', 'Rest') {
    Register-ArgumentCompleter -CommandName 'Invoke-Corral', 'corral' `
                               -ParameterName $parameter -ScriptBlock $script:CorralCompleter
}

Set-Alias -Name corral -Value Invoke-Corral

Export-ModuleMember -Function Invoke-Corral -Alias corral
