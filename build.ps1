#Requires -Version 5.1
<#
.SYNOPSIS
    src/ 의 원본을 Install-ClawdNotify.ps1 에 묶어 넣는다.
.DESCRIPTION
    배포 파일은 Install-ClawdNotify.ps1 하나로 동작해야 하므로 설정 UI 스크립트를
    Base64로 인코딩해 $Script:B64_UI 블록에 넣는다.
    설정 UI를 고친 뒤에는 반드시 이 스크립트를 실행한다.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File build.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$Root      = $PSScriptRoot
$Installer = Join-Path $Root 'Install-ClawdNotify.ps1'
$Utf8Bom   = [System.Text.UTF8Encoding]::new($true)

# 변수 이름 => 원본 파일
$Embeds = [ordered]@{
    'B64_UI' = Join-Path $Root 'src\claude-notify-settings.ps1'
}

$text = [System.IO.File]::ReadAllText($Installer, $Utf8Bom)

foreach ($name in $Embeds.Keys) {
    $src = $Embeds[$name]
    # 설치 시 UTF-8(BOM)로 다시 저장되므로, 원본의 BOM은 빼고 줄바꿈은 CRLF로 맞춘다
    $content = [System.IO.File]::ReadAllText($src, $Utf8Bom) -replace "`r?`n", "`r`n"
    $b64 = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))

    # 기존 블록과 같은 모양: 76자씩 나눈 작은따옴표 문자열 배열
    $lines = for ($i = 0; $i -lt $b64.Length; $i += 76) {
        "'" + $b64.Substring($i, [Math]::Min(76, $b64.Length - $i)) + "'"
    }
    $block = "`$Script:$name = @(`r`n" + ($lines -join ",`r`n") + "`r`n) -join ''"

    $pattern = '(?s)\$Script:' + [regex]::Escape($name) + ' = @\(.*?\) -join '''''
    if (-not [regex]::IsMatch($text, $pattern)) { throw "블록을 찾을 수 없습니다: `$Script:$name" }
    $text = [regex]::Replace($text, $pattern, { param($m) $block }, 'None')
    Write-Host "  [OK] $name <- $(Split-Path $src -Leaf) ($($content.Length) chars)" -ForegroundColor Green
}

[System.IO.File]::WriteAllText($Installer, ($text -replace "`r?`n", "`r`n"), $Utf8Bom)

# 결과가 문법적으로 올바른지 확인한다
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($Installer, [ref]$null, [ref]$errs)
if ($errs.Count -gt 0) {
    $errs | ForEach-Object { Write-Host "  [X] $_" -ForegroundColor Red }
    exit 1
}
Write-Host "  [OK] $(Split-Path $Installer -Leaf) 빌드 완료" -ForegroundColor Green
