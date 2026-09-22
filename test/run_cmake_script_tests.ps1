# Tests for the cmake helper scripts in tools/.
#
# These are build tooling, not firmware, so they are not covered by the compile time
# tests in test_config_and_gps.cpp. One of them is what stands between a too large
# image and a bricked board, so it gets tested rather than trusted.
#
#     . "$env:USERPROFILE\.pico-sdk\pico-env.ps1"
#     .\test\run_cmake_script_tests.ps1

$ErrorActionPreference = 'Stop'
$repo  = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $repo 'tools'
$cmake = (Get-Command cmake).Source

$script:pass = 0
$script:fail = 0

function Check($name, $condition, $detail) {
    if ($condition) {
        "  [ ok ] $name"
        $script:pass++
    } else {
        "  [FAIL] $name"
        if ($detail) { "         $detail" }
        $script:fail++
    }
}

# helper: run a cmake -P script, return @{ Code; Output }
function RunScript($script, $defs) {
    $args = @()
    foreach ($d in $defs) { $args += "-D$d" }
    $args += @('-P', (Join-Path $tools $script))
    $out = & $cmake @args 2>&1 | Out-String
    return @{ Code = $LASTEXITCODE; Output = $out }
}

# ---------------------------------------------------------------------------
"check_flash_layout.cmake"
# ---------------------------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("oxs_tests_" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    foreach ($case in @(@{n='small'; s=240000}, @{n='tight'; s=258000}, @{n='over'; s=266804})) {
        $f = Join-Path $tmp "$($case.n).bin"
        [IO.File]::WriteAllBytes($f, (New-Object byte[] $case.s))
    }

    $r = RunScript 'check_flash_layout.cmake' @("BIN=$tmp/small.bin", 'CONFIG_OFFSET=262144', 'RESERVED=8192')
    Check 'image well below the parameter area passes silently' `
          ($r.Code -eq 0 -and $r.Output -notmatch 'Warning|Error') $r.Output

    $r = RunScript 'check_flash_layout.cmake' @("BIN=$tmp/tight.bin", 'CONFIG_OFFSET=262144', 'RESERVED=8192')
    Check 'image with little headroom warns but still builds' `
          ($r.Code -eq 0 -and $r.Output -match 'Warning') $r.Output

    $r = RunScript 'check_flash_layout.cmake' @("BIN=$tmp/over.bin", 'CONFIG_OFFSET=262144', 'RESERVED=8192')
    Check 'image reaching into the parameter area fails the build' `
          ($r.Code -ne 0 -and $r.Output -match 'overlaps the parameter area') $r.Output

    $r = RunScript 'check_flash_layout.cmake' @("BIN=$tmp/does_not_exist.bin", 'CONFIG_OFFSET=262144', 'RESERVED=8192')
    Check 'missing image is an error, not a silent pass' ($r.Code -ne 0) $r.Output
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
"gen_version.cmake"
# ---------------------------------------------------------------------------
# Run against a throwaway repo so the real working tree is never touched.
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("oxs_ver_" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path (Join-Path $tmp 'src') | Out-Null
try {
    Set-Content -Path (Join-Path $tmp 'src\config.h') -Value '#define VERSION_BASE "9.8.7"'
    # outside the repo, like the real build/ directory, or it would count as untracked
    $out = Join-Path ([IO.Path]::GetTempPath()) ("oxs_ver_out_" + [guid]::NewGuid().ToString('N').Substring(0,8) + '.h')

    function VersionOf($h) {
        if (-not (Test-Path $h)) { return '<no header>' }
        $m = Select-String -Path $h -Pattern '#define VERSION "([^"]*)"'
        if ($m) { return $m.Matches[0].Groups[1].Value } else { return '<no define>' }
    }

    # no git repo at all
    $r = RunScript 'gen_version.cmake' @("SRC_DIR=$tmp", "OUT=$out")
    $v = VersionOf $out
    Check 'outside a git repo falls back to the base version' ($v -eq '9.8.7-nogit') "got '$v'"

    # a real repo on a named branch with one commit
    Push-Location $tmp
    git init -q -b testbranch 2>&1 | Out-Null
    git -c user.email=t@t -c user.name=t add -A 2>&1 | Out-Null
    git -c user.email=t@t -c user.name=t commit -q -m init 2>&1 | Out-Null
    $sha = (git rev-parse --short HEAD).Trim()
    Pop-Location

    Remove-Item $out -ErrorAction SilentlyContinue
    $r = RunScript 'gen_version.cmake' @("SRC_DIR=$tmp", "OUT=$out")
    $v = VersionOf $out
    Check 'clean tree gives base-branch-commit' ($v -eq "9.8.7-testbranch-$sha") "got '$v'"

    # unchanged input must not rewrite the header, or every build recompiles everything
    $before = (Get-Item $out).LastWriteTimeUtc
    Start-Sleep -Milliseconds 1100
    $r = RunScript 'gen_version.cmake' @("SRC_DIR=$tmp", "OUT=$out")
    $after = (Get-Item $out).LastWriteTimeUtc
    Check 'unchanged version leaves the header untouched' ($before -eq $after) "mtime moved: $before -> $after"

    # a modified working tree must be marked
    Set-Content -Path (Join-Path $tmp 'src\extra.cpp') -Value '// uncommitted'
    $r = RunScript 'gen_version.cmake' @("SRC_DIR=$tmp", "OUT=$out")
    $v = VersionOf $out
    Check 'modified working tree is marked dirty' ($v -eq "9.8.7-testbranch-$sha-dirty") "got '$v'"

    # branch names with a slash must not break the identifier
    Push-Location $tmp
    git checkout -q -b "feature/sub-branch" 2>&1 | Out-Null
    Pop-Location
    $r = RunScript 'gen_version.cmake' @("SRC_DIR=$tmp", "OUT=$out")
    $v = VersionOf $out
    Check 'branch name is sanitised' ($v -match '^9\.8\.7-feature-sub-branch-') "got '$v'"
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    if ($out) { Remove-Item -Force $out -ErrorAction SilentlyContinue }
}

""
"$script:pass passed, $script:fail failed"
if ($script:fail -gt 0) { exit 1 }
