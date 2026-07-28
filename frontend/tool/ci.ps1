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
    Invoke-CheckedCommand 'flutter' @('pub', 'get', '--enforce-lockfile')
    & (Join-Path $PSScriptRoot 'generate.ps1')
    Invoke-CheckedCommand 'git' @('diff', '--exit-code', '--', 'lib')
    Invoke-CheckedCommand 'dart' @(
        'format',
        '--output=none',
        '--set-exit-if-changed',
        'lib',
        'test',
        'integration_test'
    )
    Invoke-CheckedCommand 'flutter' @(
        'analyze',
        '--fatal-infos',
        '--fatal-warnings'
    )
    Invoke-CheckedCommand 'flutter' @('test')
    Invoke-CheckedCommand 'flutter' @(
        'build',
        'apk',
        '--debug',
        '--flavor',
        'development',
        '--target',
        'lib/main_development.dart'
    )
    Invoke-CheckedCommand 'flutter' @(
        'build',
        'apk',
        '--release',
        '--flavor',
        'production',
        '--target',
        'lib/main_production.dart'
    )
    Invoke-CheckedCommand 'flutter' @(
        'build',
        'web',
        '--release',
        '--target',
        'lib/main_production.dart'
    )
}
finally {
    Pop-Location
}
