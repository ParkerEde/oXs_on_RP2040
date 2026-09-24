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

# ---------------------------------------------------------------------------
"stage_release.cmake"
# ---------------------------------------------------------------------------
$tmp = Join-Path ([IO.Path]::GetTempPath()) ("oxs_dist_" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $hdr  = Join-Path $tmp 'oxs_version.h'
    $uf2  = Join-Path $tmp 'oXs_somebranch.uf2'
    $dist = Join-Path $tmp 'dist'
    Set-Content -Path $hdr -Value '#define VERSION "9.8.7-somebranch-abc1234"'
    [IO.File]::WriteAllBytes($uf2, [byte[]](1,2,3,4,5))

    $r = RunScript 'stage_release.cmake' @("UF2=$uf2", "VERSION_HEADER=$hdr", "DIST_DIR=$dist")
    $staged = Join-Path $dist 'oXs_9.8.7-somebranch-abc1234.uf2'
    Check 'staged file is named after the version in the header' `
          ($r.Code -eq 0 -and (Test-Path $staged)) $r.Output
    Check 'staged file is a byte identical copy' `
          ((Test-Path $staged) -and ((Get-FileHash $staged).Hash -eq (Get-FileHash $uf2).Hash)) ''

    # a build from a dirty tree must be recognisable by its file name alone
    Set-Content -Path $hdr -Value '#define VERSION "9.8.7-somebranch-abc1234-dirty"'
    $r = RunScript 'stage_release.cmake' @("UF2=$uf2", "VERSION_HEADER=$hdr", "DIST_DIR=$dist")
    $dirty = Join-Path $dist 'oXs_9.8.7-somebranch-abc1234-dirty.uf2'
    Check 'dirty build is staged under its dirty name' ((Test-Path $dirty)) $r.Output
    Check 'the previous build is no longer in dist' (-not (Test-Path $staged)) `
          'stale artifacts would make it ambiguous which file to hand out'
    Check 'dist holds exactly one uf2' `
          (@(Get-ChildItem $dist -Filter *.uf2 -ErrorAction SilentlyContinue).Count -eq 1) ''

    $r = RunScript 'stage_release.cmake' @("UF2=$tmp/missing.uf2", "VERSION_HEADER=$hdr", "DIST_DIR=$dist")
    Check 'missing uf2 is an error' ($r.Code -ne 0) $r.Output

    $r = RunScript 'stage_release.cmake' @("UF2=$uf2", "VERSION_HEADER=$tmp/missing.h", "DIST_DIR=$dist")
    Check 'missing version header is an error' ($r.Code -ne 0) $r.Output
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

# ---------------------------------------------------------------------------
"CMakeLists.txt: OXS_COPY_UF2_TO"
# ---------------------------------------------------------------------------
# The release refresh silently did nothing for half a year: POST_BUILD commands run
# with the build directory as their working directory, so the documented "." copied
# the artifact onto itself and still exited 0. The committed oXs.uf2 went stale while
# the procedure looked like it worked.
#
# This logic lives in CMakeLists.txt rather than tools/, so it cannot be driven with
# cmake -P. Instead the real project is configured into a throwaway build directory
# and the generated build system is asked where the copy would actually go. That is
# the step that was wrong; whether cmake -E copy then works is cmake's problem.
#
# Configuring costs a few seconds per case, which is why the cases are few.

# pull the destination out of the generated copy command, or $null if there is none
function CopyDestination($buildDir) {
    $ninja = Join-Path $buildDir 'build.ninja'
    if (-not (Test-Path $ninja)) { return $null }
    $hit = Select-String -Path $ninja -Pattern '-E copy' | Select-Object -First 1
    if (-not $hit) { return $null }
    # cmake -E copy <source> <destination>, destination last before the closing quote
    # of the cmd.exe /C string; either argument may be quoted if it contains spaces
    if ($hit.Line -match '-E copy\s+(?:"([^"]+)"|(\S+))\s+(?:"([^"]+)"|([^\s"]+))') {
        $dest = if ($Matches[3]) { $Matches[3] } else { $Matches[4] }
        return ($dest -replace '\\', '/').TrimEnd('/')
    }
    return $null
}

function ConfigureWith($buildDir, $defs) {
    $args = @('-S', $repo, '-B', $buildDir, '-G', 'Ninja')
    foreach ($d in $defs) { $args += "-D$d" }
    & $cmake @args 2>&1 | Out-Null
    return $LASTEXITCODE
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("oxs_tests_" + [guid]::NewGuid().ToString('N').Substring(0,8))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $repoNorm = ($repo -replace '\\', '/').TrimEnd('/')

    # the regression: "." must mean the repo root, not the build directory
    $b = Join-Path $tmp 'dot'
    $code = ConfigureWith $b @('OXS_COPY_UF2_TO=.')
    $dest = CopyDestination $b
    Check 'a relative destination resolves against the repo root' `
          ($code -eq 0 -and $dest -eq $repoNorm) "configure=$code dest=$dest expected=$repoNorm"
    # independent of where it points: a destination that reaches the generated command
    # still relative would be read against the build directory, which is the whole bug
    Check 'the generated destination is absolute' `
          ($dest -match '^([A-Za-z]:/|/)') "dest=$dest"

    # a relative subdirectory follows the same rule
    $b = Join-Path $tmp 'sub'
    $null = ConfigureWith $b @('OXS_COPY_UF2_TO=dist/hand-out')
    Check 'a relative subdirectory hangs off the repo root too' `
          ((CopyDestination $b) -eq "$repoNorm/dist/hand-out") "dest=$(CopyDestination $b)"

    # an absolute path must survive untouched, this is the flash-a-board case
    $drive = Join-Path $tmp 'drive'
    $b = Join-Path $tmp 'abs'
    $null = ConfigureWith $b @("OXS_COPY_UF2_TO=$drive")
    Check 'an absolute destination is left alone' `
          ((CopyDestination $b) -eq (($drive -replace '\\', '/').TrimEnd('/'))) "dest=$(CopyDestination $b)"

    # the default must not touch anything outside the build directory
    $b = Join-Path $tmp 'none'
    $null = ConfigureWith $b @()
    Check 'no destination means no copy command at all' `
          ((CopyDestination $b) -eq $null) 'a default build must leave the working tree alone'
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}

""
"$script:pass passed, $script:fail failed"
# explicit, or the exit status would be that of the last cmake call - which the error
# cases deliberately make non-zero, so a fully passing run would look like a failure
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
