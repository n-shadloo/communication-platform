$ErrorActionPreference = 'Stop'

function Invoke-CheckedCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Executable exited with code $LASTEXITCODE."
    }
}

Push-Location (Join-Path $PSScriptRoot '..')
try {
    Invoke-CheckedCommand 'flutter' @('gen-l10n')
    Invoke-CheckedCommand 'dart' @('run', 'build_runner', 'build')
}
finally {
    Pop-Location
}
