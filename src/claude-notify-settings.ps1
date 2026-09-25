#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code 알림 설정 UI
.DESCRIPTION
    settings.json의 Notification/Stop hook을 그래픽 화면에서 설정한다.
    표시 시간, 발화 조건, 이미지, 메시지, 알림음, 이벤트 on/off, 표시 언어를 다룬다.

    이 파일이 원본이다. 수정 후 build.ps1을 실행하면 Install-ClawdNotify.ps1에 반영된다.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$Version = 'v1.2.1'

# ---------------------------------------------------------------- 경로
$ClaudeDir    = Join-Path $env:USERPROFILE '.claude'
$AssetsDir    = Join-Path $ClaudeDir 'assets'
$SettingsPath = Join-Path $ClaudeDir 'settings.json'
$NotifyScript = Join-Path $ClaudeDir 'claude-notify.ps1'
$ConfigPath   = Join-Path $ClaudeDir 'claude-notify-config.json'

# ---------------------------------------------------------------- 언어
# 설치 스크립트/알림 스크립트와 같은 설정 파일을 쓴다. 없으면 Windows 표시 언어를 따른다.
function Get-Language {
    try {
        $lang = (Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json).language
        if ($lang -in 'ko', 'en') { return $lang }
    } catch { }
    if ([System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq 'ko') { 'ko' } else { 'en' }
}

function Save-Language {
    param([string]$Lang)
    $cfg = [PSCustomObject]@{}
    try { $cfg = Get-Content $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
    $cfg | Add-Member -NotePropertyName 'language' -NotePropertyValue $Lang -Force
    [System.IO.File]::WriteAllText($ConfigPath, ($cfg | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
}

$Lang = Get-Language

# 한국어/영어 문자열 중 현재 언어에 맞는 것을 고른다
function T {
    param([string]$Ko, [string]$En)
    if ($script:Lang -eq 'en') { $En } else { $Ko }
}

# 기본 알림 문구. 저장된 문구가 어느 한쪽 기본값과 같으면 현재 언어의 기본값으로 바꿔 보여준다.
# claude-notify.ps1도 같은 표를 써서 알림을 띄울 때 번역한다.
$DefaultMessages = @(
    @{ ko = '확인이 필요합니다.';     en = 'Claude needs your attention.' }
    @{ ko = '작업이 완료되었습니다.'; en = 'Task completed.' }
)
function Convert-DefaultMessage {
    param([string]$Message)
    foreach ($m in $DefaultMessages) {
        if ($Message -eq $m.ko -or $Message -eq $m.en) { return $m[$script:Lang] }
    }
    return $Message
}

if (-not (Test-Path $NotifyScript)) {
    [System.Windows.Forms.MessageBox]::Show(
        (T "알림 스크립트를 찾을 수 없습니다:`n$NotifyScript`n`n먼저 install.bat으로 설치하세요." `
           "Notification script not found:`n$NotifyScript`n`nRun install.bat first."),
        (T 'Claude 알림 설정' 'Claude Notification Settings'), 'OK', 'Error') | Out-Null
    exit 1
}

# ---------------------------------------------------------------- 설정 입출력
function Read-Settings {
    if (-not (Test-Path $SettingsPath)) { return [PSCustomObject]@{} }
    $raw = Get-Content $SettingsPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) { return [PSCustomObject]@{} }
    return $raw | ConvertFrom-Json
}

# hook 커맨드 문자열에서 현재 설정값을 역으로 읽어낸다.
function Parse-Command {
    param([string]$Cmd)
    $r = @{
        Message  = ''
        Title    = 'Claude Code'
        Hero     = ''
        Logo     = ''
        Circle   = $false
        Scenario = 'reminder'
        Sound    = 'Default'
        Loop     = $false
    }
    if ([string]::IsNullOrWhiteSpace($Cmd)) { return $r }
    if ($Cmd -match '-Message\s+"([^"]*)"')  { $r.Message  = $Matches[1] }
    if ($Cmd -match '-Title\s+"([^"]*)"')    { $r.Title    = $Matches[1] }
    if ($Cmd -match '-Hero\s+"([^"]*)"')     { $r.Hero     = $Matches[1] }
    if ($Cmd -match '-Logo\s+"([^"]*)"')     { $r.Logo     = $Matches[1] }
    if ($Cmd -match '-Scenario\s+(\w+)')     { $r.Scenario = $Matches[1] }
    if ($Cmd -match '-Sound\s+(\w+)')        { $r.Sound    = $Matches[1] }
    $r.Circle = $Cmd -match '-LogoCircle'
    $r.Loop   = $Cmd -match '-LoopSound'
    return $r
}

function Build-Command {
    param([hashtable]$C)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "')
    [void]$sb.Append($NotifyScript)
    [void]$sb.Append('"')
    [void]$sb.Append(' -Message "' + ($C.Message -replace '"','') + '"')
    if ($C.Title -and $C.Title -ne 'Claude Code') {
        [void]$sb.Append(' -Title "' + ($C.Title -replace '"','') + '"')
    }
    if ($C.Scenario -ne 'reminder') { [void]$sb.Append(' -Scenario ' + $C.Scenario) }
    if ($C.Hero) { [void]$sb.Append(' -Hero "' + $C.Hero + '"') }
    if ($C.Logo) {
        [void]$sb.Append(' -Logo "' + $C.Logo + '"')
        if ($C.Circle) { [void]$sb.Append(' -LogoCircle') }
    }
    if ($C.Sound -ne 'Default') { [void]$sb.Append(' -Sound ' + $C.Sound) }
    if ($C.Loop) { [void]$sb.Append(' -LoopSound') }
    return $sb.ToString()
}

# 언어를 바꾸면 창을 닫고 새 언어로 다시 그린다
$Script:Restart = $true
while ($Script:Restart) {
$Script:Restart = $false

# ---------------------------------------------------------------- 상수
# Notification 이벤트의 발화 조건(matcher). 문서 기준.
$NotifTypes = [ordered]@{
    'permission_prompt'       = T '승인 대기 (도구 실행 허가, 약 6초 후)'     'Permission prompt (tool approval, after ~6s)'
    'idle_prompt'             = T '유휴 상태 (응답 후 입력 없음, 약 60초 후)' 'Idle (no input after reply, after ~60s)'
    'auth_success'            = T '인증 완료'                                 'Authentication succeeded'
    'agent_needs_input'       = T '백그라운드 에이전트가 입력 대기'           'Background agent needs input'
    'agent_completed'         = T '백그라운드 에이전트 완료'                  'Background agent completed'
    'elicitation_dialog'      = T 'MCP 입력 폼 대기'                          'MCP input form waiting'
    'quota_auto_resume_fired' = T '사용량 제한 후 자동 재개'                  'Auto-resumed after usage limit'
}

$Sounds = [ordered]@{
    'Default'  = T '기본음'            'Default'
    'IM'       = T '메시지음'          'Instant message'
    'Mail'     = T '메일음'            'Mail'
    'Reminder' = T '알림음 (Reminder)' 'Reminder'
    'SMS'      = T 'SMS음'             'SMS'
    'Alarm'    = T '알람음 (반복)'     'Alarm (looping)'
    'Call'     = T '전화벨 (반복)'     'Call (looping)'
    'Silent'   = T '무음'              'Silent'
}

# ---------------------------------------------------------------- 현재 상태 로드
$settings = Read-Settings
$curNotif = $null; $curStop = $null
$notifMatcher = ''
$notifEnabled = $false; $stopEnabled = $false

if ($settings.PSObject.Properties['hooks']) {
    if ($settings.hooks.PSObject.Properties['Notification']) {
        $e = $settings.hooks.Notification[0]
        $notifMatcher = [string]$e.matcher
        $curNotif = Parse-Command $e.hooks[0].command
        $notifEnabled = $e.hooks[0].command -like '*claude-notify.ps1*'
    }
    if ($settings.hooks.PSObject.Properties['Stop']) {
        $e = $settings.hooks.Stop[0]
        $curStop = Parse-Command $e.hooks[0].command
        $stopEnabled = $e.hooks[0].command -like '*claude-notify.ps1*'
    }
}
if (-not $curNotif) {
    $curNotif = @{ Message=$DefaultMessages[0][$Lang]; Title='Claude Code'
        Hero=(Join-Path $AssetsDir 'clawd-ask-hero.png'); Logo=(Join-Path $AssetsDir 'clawd_question.png'); Circle=$false
        Scenario='reminder'; Sound='Default'; Loop=$false }
}
if (-not $curStop) {
    $curStop = @{ Message=$DefaultMessages[1][$Lang]; Title='Claude Code'
        Hero=(Join-Path $AssetsDir 'clawd-done-hero.png'); Logo=(Join-Path $AssetsDir 'clawd_done.png'); Circle=$false
        Scenario='reminder'; Sound='Default'; Loop=$false }
}
$curNotif.Message = Convert-DefaultMessage $curNotif.Message
$curStop.Message  = Convert-DefaultMessage $curStop.Message
# 기존 설정에 이미지가 없으면 기본 이미지를 채워 넣는다.
# 크기를 전환했을 때 경로가 비어 있어 알림이 안 뜨는 일을 막는다.
if (-not $curNotif.Hero) { $curNotif.Hero = Join-Path $AssetsDir 'clawd-ask-hero.png' }
if (-not $curNotif.Logo) { $curNotif.Logo = Join-Path $AssetsDir 'clawd_question.png' }
if (-not $curStop.Hero)  { $curStop.Hero  = Join-Path $AssetsDir 'clawd-done-hero.png' }
if (-not $curStop.Logo)  { $curStop.Logo  = Join-Path $AssetsDir 'clawd_done.png' }


# ---------------------------------------------------------------- UI 구성
$form = New-Object System.Windows.Forms.Form
$form.Text = (T 'Claude Code 알림 설정' 'Claude Code Notification Settings') + "  $Version"
$form.Size = New-Object System.Drawing.Size(660, 906)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Malgun Gothic', 9)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Location = New-Object System.Drawing.Point(12, 12)
$tabs.Size = New-Object System.Drawing.Size(620, 766)
$form.Controls.Add($tabs)

# 이벤트 탭을 만드는 공통 함수 (Notification / Stop 이 거의 동일한 구조)
function New-EventTab {
    param([string]$TabName, [hashtable]$Cfg, [bool]$Enabled, [bool]$IsNotification)

    # 클로저가 값으로 캡처하도록 지역 변수에 담는다.
    # $script:AssetsDir는 클로저 안에서 null이 되어 Test-Path가 실패한다.
    # 클로저 안에서 쓰는 문자열도 같은 이유로 미리 만들어 둔다.
    $initDir = $AssetsDir
    $imgFilter = T '이미지 파일|*.png;*.jpg;*.jpeg;*.gif|모든 파일|*.*' 'Image files|*.png;*.jpg;*.jpeg;*.gif|All files|*.*'
    $msgTestFail = T '알림 실행 실패' 'Failed to show notification'
    $msgError = T '오류' 'Error'

    $tab = New-Object System.Windows.Forms.TabPage
    $tab.Text = $TabName
    $tab.BackColor = [System.Drawing.Color]::White
    $tab.Padding = New-Object System.Windows.Forms.Padding(10)

    $y = 14

    # --- 사용 여부 ---
    $chkOn = New-Object System.Windows.Forms.CheckBox
    $chkOn.Text = T '이 알림 사용' 'Enable this notification'
    $chkOn.Location = New-Object System.Drawing.Point(16, $y)
    $chkOn.Size = New-Object System.Drawing.Size(300, 24)
    $chkOn.Checked = $Enabled
    $chkOn.Font = New-Object System.Drawing.Font('Malgun Gothic', 10, [System.Drawing.FontStyle]::Bold)
    $tab.Controls.Add($chkOn)
    $y += 34

    # --- 메시지 ---
    $lblMsg = New-Object System.Windows.Forms.Label
    $lblMsg.Text = T '알림 문구' 'Message'
    $lblMsg.Location = New-Object System.Drawing.Point(16, $y)
    $lblMsg.Size = New-Object System.Drawing.Size(120, 20)
    $tab.Controls.Add($lblMsg)
    $txtMsg = New-Object System.Windows.Forms.TextBox
    $txtMsg.Location = New-Object System.Drawing.Point(140, ($y-3))
    $txtMsg.Size = New-Object System.Drawing.Size(440, 24)
    $txtMsg.Text = $Cfg.Message
    $tab.Controls.Add($txtMsg)
    $y += 32

    $lblTitle = New-Object System.Windows.Forms.Label
    $lblTitle.Text = T '제목' 'Title'
    $lblTitle.Location = New-Object System.Drawing.Point(16, $y)
    $lblTitle.Size = New-Object System.Drawing.Size(120, 20)
    $tab.Controls.Add($lblTitle)
    $txtTitle = New-Object System.Windows.Forms.TextBox
    $txtTitle.Location = New-Object System.Drawing.Point(140, ($y-3))
    $txtTitle.Size = New-Object System.Drawing.Size(440, 24)
    $txtTitle.Text = $Cfg.Title
    $tab.Controls.Add($txtTitle)
    $y += 40

    # --- 표시 시간 ---
    $grpTime = New-Object System.Windows.Forms.GroupBox
    $grpTime.Text = T '창이 떠있는 시간' 'How long the notification stays'
    $grpTime.Location = New-Object System.Drawing.Point(16, $y)
    $grpTime.Size = New-Object System.Drawing.Size(564, 78)
    $tab.Controls.Add($grpTime)

    $rdoStay = New-Object System.Windows.Forms.RadioButton
    $rdoStay.Text = T '닫을 때까지 유지' 'Until dismissed'
    $rdoStay.Location = New-Object System.Drawing.Point(16, 24)
    $rdoStay.Size = New-Object System.Drawing.Size(180, 22)
    $rdoStay.Checked = ($Cfg.Scenario -eq 'reminder')
    $grpTime.Controls.Add($rdoStay)

    $rdoAuto = New-Object System.Windows.Forms.RadioButton
    $rdoAuto.Text = T '약 5~7초 후 자동으로 사라짐' 'Auto-hide after ~5-7 seconds'
    $rdoAuto.Location = New-Object System.Drawing.Point(210, 24)
    $rdoAuto.Size = New-Object System.Drawing.Size(260, 22)
    $rdoAuto.Checked = ($Cfg.Scenario -eq 'default')
    $grpTime.Controls.Add($rdoAuto)

    $lblTimeNote = New-Object System.Windows.Forms.Label
    $lblTimeNote.Text = T 'Windows는 초 단위 지정을 지원하지 않습니다. 사라진 알림은 알림 센터(Win+N)에 남습니다.' `
                          'Custom durations are not supported. Hidden toasts stay in Notification Center (Win+N).'
    $lblTimeNote.Location = New-Object System.Drawing.Point(16, 50)
    $lblTimeNote.Size = New-Object System.Drawing.Size(540, 20)
    $lblTimeNote.ForeColor = [System.Drawing.Color]::Gray
    $grpTime.Controls.Add($lblTimeNote)
    $y += 88

    # --- 발화 조건 (Notification 전용) ---
    $clbCond = $null
    if ($IsNotification) {
        $grpCond = New-Object System.Windows.Forms.GroupBox
        $grpCond.Text = T '창이 뜨는 조건' 'When to notify'
        $grpCond.Location = New-Object System.Drawing.Point(16, $y)
        $grpCond.Size = New-Object System.Drawing.Size(564, 168)
        $tab.Controls.Add($grpCond)

        $chkAll = New-Object System.Windows.Forms.CheckBox
        $chkAll.Text = T '모든 조건에서 알림 (권장)' 'Notify on all conditions (recommended)'
        $chkAll.Location = New-Object System.Drawing.Point(16, 22)
        $chkAll.Size = New-Object System.Drawing.Size(300, 22)
        $chkAll.Checked = [string]::IsNullOrWhiteSpace($script:notifMatcher)
        $grpCond.Controls.Add($chkAll)

        $clbCond = New-Object System.Windows.Forms.CheckedListBox
        $clbCond.Location = New-Object System.Drawing.Point(16, 48)
        $clbCond.Size = New-Object System.Drawing.Size(534, 110)
        $clbCond.CheckOnClick = $true
        $selected = @()
        if (-not [string]::IsNullOrWhiteSpace($script:notifMatcher)) {
            $selected = $script:notifMatcher -split '\|'
        }
        foreach ($k in $NotifTypes.Keys) {
            $idx = $clbCond.Items.Add($NotifTypes[$k])
            if ($selected -contains $k) { $clbCond.SetItemChecked($idx, $true) }
        }
        $clbCond.Enabled = -not $chkAll.Checked
        $chkAll.Add_CheckedChanged({ $clbCond.Enabled = -not $chkAll.Checked }.GetNewClosure())
        $grpCond.Controls.Add($clbCond)
        $y += 178
    } else {
        $lblStopNote = New-Object System.Windows.Forms.Label
        $lblStopNote.Text = T '창이 뜨는 조건: Claude가 응답을 마칠 때 (백그라운드 작업이 남아 있으면 생략)' `
                              'When to notify: when Claude finishes a response (skipped while background tasks run)'
        $lblStopNote.Location = New-Object System.Drawing.Point(16, $y)
        $lblStopNote.Size = New-Object System.Drawing.Size(564, 22)
        $lblStopNote.ForeColor = [System.Drawing.Color]::DimGray
        $tab.Controls.Add($lblStopNote)
        $y += 32
    }

    # --- 이미지 ---
    $grpImg = New-Object System.Windows.Forms.GroupBox
    $grpImg.Text = T '그림 설정' 'Image'
    $grpImg.Location = New-Object System.Drawing.Point(16, $y)
    $grpImg.Size = New-Object System.Drawing.Size(564, 236)
    $tab.Controls.Add($grpImg)

    # --- 창 크기: Hero(큰 창) / Logo(작은 창) / 없음(텍스트만) ---
    $lblSize = New-Object System.Windows.Forms.Label
    $lblSize.Text = T '창 크기' 'Size'
    $lblSize.Location = New-Object System.Drawing.Point(16, 24)
    $lblSize.Size = New-Object System.Drawing.Size(80, 20)
    $grpImg.Controls.Add($lblSize)

    $rdoBig = New-Object System.Windows.Forms.RadioButton
    $rdoBig.Text = T '큰 창 (배너)' 'Large (banner)'
    $rdoBig.Location = New-Object System.Drawing.Point(100, 22)
    $rdoBig.Size = New-Object System.Drawing.Size(116, 22)
    $grpImg.Controls.Add($rdoBig)

    $rdoSmall = New-Object System.Windows.Forms.RadioButton
    $rdoSmall.Text = T '작은 창 (아이콘)' 'Small (icon)'
    $rdoSmall.Location = New-Object System.Drawing.Point(222, 22)
    $rdoSmall.Size = New-Object System.Drawing.Size(136, 22)
    $grpImg.Controls.Add($rdoSmall)

    $rdoText = New-Object System.Windows.Forms.RadioButton
    $rdoText.Text = T '텍스트만' 'Text only'
    $rdoText.Location = New-Object System.Drawing.Point(364, 22)
    $rdoText.Size = New-Object System.Drawing.Size(92, 22)
    $grpImg.Controls.Add($rdoText)

    $chkCircle = New-Object System.Windows.Forms.CheckBox
    $chkCircle.Text = T '원형' 'Circle'
    $chkCircle.Location = New-Object System.Drawing.Point(462, 22)
    $chkCircle.Size = New-Object System.Drawing.Size(64, 22)
    $chkCircle.Checked = $Cfg.Circle
    $grpImg.Controls.Add($chkCircle)

    # --- 배너 이미지 (큰 창용) ---
    $lblHero = New-Object System.Windows.Forms.Label
    $lblHero.Text = T '배너 (큰 창)' 'Banner'
    $lblHero.Location = New-Object System.Drawing.Point(16, 58)
    $lblHero.Size = New-Object System.Drawing.Size(84, 20)
    $grpImg.Controls.Add($lblHero)

    $txtHero = New-Object System.Windows.Forms.TextBox
    $txtHero.Location = New-Object System.Drawing.Point(104, 55)
    $txtHero.Size = New-Object System.Drawing.Size(306, 24)
    $txtHero.Text = $Cfg.Hero
    $grpImg.Controls.Add($txtHero)

    $btnHero = New-Object System.Windows.Forms.Button
    $btnHero.Text = T '찾아보기' 'Browse'
    $btnHero.Location = New-Object System.Drawing.Point(418, 54)
    $btnHero.Size = New-Object System.Drawing.Size(74, 26)
    $grpImg.Controls.Add($btnHero)

    $btnHeroClear = New-Object System.Windows.Forms.Button
    $btnHeroClear.Text = T '지움' 'Clear'
    $btnHeroClear.Location = New-Object System.Drawing.Point(496, 54)
    $btnHeroClear.Size = New-Object System.Drawing.Size(54, 26)
    $grpImg.Controls.Add($btnHeroClear)

    # --- 아이콘 이미지 (작은 창용, 정사각형 권장) ---
    $lblLogo = New-Object System.Windows.Forms.Label
    $lblLogo.Text = T '아이콘 (작은 창)' 'Icon'
    $lblLogo.Location = New-Object System.Drawing.Point(16, 90)
    $lblLogo.Size = New-Object System.Drawing.Size(84, 32)
    $grpImg.Controls.Add($lblLogo)

    $txtLogo = New-Object System.Windows.Forms.TextBox
    $txtLogo.Location = New-Object System.Drawing.Point(104, 87)
    $txtLogo.Size = New-Object System.Drawing.Size(306, 24)
    $txtLogo.Text = $Cfg.Logo
    $grpImg.Controls.Add($txtLogo)

    $btnLogo = New-Object System.Windows.Forms.Button
    $btnLogo.Text = T '찾아보기' 'Browse'
    $btnLogo.Location = New-Object System.Drawing.Point(418, 86)
    $btnLogo.Size = New-Object System.Drawing.Size(74, 26)
    $grpImg.Controls.Add($btnLogo)

    $btnLogoClear = New-Object System.Windows.Forms.Button
    $btnLogoClear.Text = T '지움' 'Clear'
    $btnLogoClear.Location = New-Object System.Drawing.Point(496, 86)
    $btnLogoClear.Size = New-Object System.Drawing.Size(54, 26)
    $grpImg.Controls.Add($btnLogoClear)

    # --- 미리보기 2개: 배너용(가로), 아이콘용(정사각) ---
    $picPrev = New-Object System.Windows.Forms.PictureBox
    $picPrev.Location = New-Object System.Drawing.Point(104, 120)
    $picPrev.Size = New-Object System.Drawing.Size(152, 76)
    $picPrev.SizeMode = 'Zoom'
    $picPrev.BorderStyle = 'FixedSingle'
    $picPrev.BackColor = [System.Drawing.Color]::WhiteSmoke
    $grpImg.Controls.Add($picPrev)

    $picLogo = New-Object System.Windows.Forms.PictureBox
    $picLogo.Location = New-Object System.Drawing.Point(264, 120)
    $picLogo.Size = New-Object System.Drawing.Size(76, 76)
    $picLogo.SizeMode = 'Zoom'
    $picLogo.BorderStyle = 'FixedSingle'
    $picLogo.BackColor = [System.Drawing.Color]::WhiteSmoke
    $grpImg.Controls.Add($picLogo)

    # 미리보기 갱신: 파일 잠금을 피하려고 스트림에서 복사본을 만든다
    $updatePrev = {
        param($path, $box)
        if ($box.Image) { $box.Image.Dispose(); $box.Image = $null }
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path $path)) { return }
        try {
            $bytes = [System.IO.File]::ReadAllBytes($path)
            $ms = New-Object System.IO.MemoryStream(,$bytes)
            $box.Image = [System.Drawing.Image]::FromStream($ms)
        } catch { }
    }

    # 저장된 설정으로 초기 선택을 정한다
    if ($Cfg.Logo) { $rdoSmall.Checked = $true }
    elseif ($Cfg.Hero) { $rdoBig.Checked = $true }
    else { $rdoText.Checked = $true }

    # 선택한 크기에 해당하는 입력만 활성화한다
    $syncSize = {
        $big = $rdoBig.Checked
        $small = $rdoSmall.Checked
        $txtHero.Enabled = $big
        $btnHero.Enabled = $big
        $btnHeroClear.Enabled = $big
        $txtLogo.Enabled = $small
        $btnLogo.Enabled = $small
        $btnLogoClear.Enabled = $small
        $chkCircle.Enabled = $small
    }.GetNewClosure()
    & $syncSize
    $rdoBig.Add_CheckedChanged($syncSize)
    $rdoSmall.Add_CheckedChanged($syncSize)
    $rdoText.Add_CheckedChanged($syncSize)

    & $updatePrev $txtHero.Text $picPrev
    & $updatePrev $txtLogo.Text $picLogo

    $btnHero.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = $imgFilter
        if ($initDir -and (Test-Path $initDir)) { $dlg.InitialDirectory = $initDir }
        if ($dlg.ShowDialog() -eq 'OK') {
            $txtHero.Text = $dlg.FileName
            & $updatePrev $dlg.FileName $picPrev
        }
    }.GetNewClosure())

    $btnHeroClear.Add_Click({
        $txtHero.Text = ''
        & $updatePrev '' $picPrev
    }.GetNewClosure())

    $btnLogo.Add_Click({
        $dlg = New-Object System.Windows.Forms.OpenFileDialog
        $dlg.Filter = $imgFilter
        if ($initDir -and (Test-Path $initDir)) { $dlg.InitialDirectory = $initDir }
        if ($dlg.ShowDialog() -eq 'OK') {
            $txtLogo.Text = $dlg.FileName
            & $updatePrev $dlg.FileName $picLogo
        }
    }.GetNewClosure())

    $btnLogoClear.Add_Click({
        $txtLogo.Text = ''
        & $updatePrev '' $picLogo
    }.GetNewClosure())

    $lblImgNote = New-Object System.Windows.Forms.Label
    $lblImgNote.Text = T "배너 364x180 권장`n아이콘 256x256 정사각형 권장`n`n절대 경로만 동작합니다.`n알림은 주 모니터에 표시됩니다." `
                         "Banner: 364x180`nIcon: 256x256 (square)`n`nAbsolute paths only.`nShown on the primary monitor."
    $lblImgNote.Location = New-Object System.Drawing.Point(350, 120)
    $lblImgNote.Size = New-Object System.Drawing.Size(200, 80)
    $lblImgNote.ForeColor = [System.Drawing.Color]::Gray
    $grpImg.Controls.Add($lblImgNote)
    $y += 246

    # --- 알림음 ---
    $lblSnd = New-Object System.Windows.Forms.Label
    $lblSnd.Text = T '알림음' 'Sound'
    $lblSnd.Location = New-Object System.Drawing.Point(16, ($y+4))
    $lblSnd.Size = New-Object System.Drawing.Size(120, 20)
    $tab.Controls.Add($lblSnd)

    $cmbSnd = New-Object System.Windows.Forms.ComboBox
    $cmbSnd.Location = New-Object System.Drawing.Point(140, $y)
    $cmbSnd.Size = New-Object System.Drawing.Size(200, 24)
    $cmbSnd.DropDownStyle = 'DropDownList'
    foreach ($k in $Sounds.Keys) { [void]$cmbSnd.Items.Add($Sounds[$k]) }
    $sIdx = @($Sounds.Keys).IndexOf($Cfg.Sound)
    $cmbSnd.SelectedIndex = if ($sIdx -ge 0) { $sIdx } else { 0 }
    $tab.Controls.Add($cmbSnd)

    $chkLoop = New-Object System.Windows.Forms.CheckBox
    $chkLoop.Text = T '반복 재생 (알람/전화벨만)' 'Loop (alarm/call only)'
    $chkLoop.Location = New-Object System.Drawing.Point(352, ($y+2))
    $chkLoop.Size = New-Object System.Drawing.Size(220, 22)
    $chkLoop.Checked = $Cfg.Loop
    $tab.Controls.Add($chkLoop)
    $y += 38

    # --- 미리보기 버튼 ---
    $btnTest = New-Object System.Windows.Forms.Button
    $btnTest.Text = T '이 설정으로 알림 띄워보기' 'Send a test notification'
    $btnTest.Location = New-Object System.Drawing.Point(16, $y)
    $btnTest.Size = New-Object System.Drawing.Size(220, 30)
    $tab.Controls.Add($btnTest)

    $btnTest.Add_Click({
        $sndKey = @($Sounds.Keys)[$cmbSnd.SelectedIndex]
        $cfg = @{
            Message  = $txtMsg.Text
            Title    = $txtTitle.Text
            Scenario = $(if ($rdoStay.Checked) { 'reminder' } else { 'default' })
            Hero     = $(if ($rdoBig.Checked) { $txtHero.Text } else { '' })
            Logo     = $(if ($rdoSmall.Checked) { $txtLogo.Text } else { '' })
            Circle   = $chkCircle.Checked
            Sound    = $sndKey
            Loop     = $chkLoop.Checked
        }
        $cmd = Build-Command $cfg
        try {
            & cmd.exe /c $cmd 2>&1 | Out-Null
        } catch {
            [System.Windows.Forms.MessageBox]::Show("${msgTestFail}:`n$($_.Exception.Message)",
                $msgError,'OK','Error') | Out-Null
        }
    }.GetNewClosure())

    # 컨트롤 참조를 탭에 붙여 저장 시 읽을 수 있게 한다
    $tab | Add-Member -NotePropertyName Ctl -NotePropertyValue @{
        On=$chkOn; Msg=$txtMsg; Title=$txtTitle; Stay=$rdoStay
        Hero=$txtHero; Snd=$cmbSnd; Loop=$chkLoop; Cond=$clbCond
        Big=$rdoBig; Small=$rdoSmall; TextOnly=$rdoText; Circle=$chkCircle
        Logo=$txtLogo
        All=$(if ($IsNotification) { $grpCond.Controls[0] } else { $null })
    } -Force

    return $tab
}

$tabNotif = New-EventTab -TabName (T '확인 요청 (Notification)' 'Needs attention (Notification)') -Cfg $curNotif -Enabled $notifEnabled -IsNotification $true
$tabStop  = New-EventTab -TabName (T '작업 완료 (Stop)' 'Task done (Stop)') -Cfg $curStop -Enabled $stopEnabled -IsNotification $false
$tabs.TabPages.Add($tabNotif)
$tabs.TabPages.Add($tabStop)

# ---------------------------------------------------------------- 하단 버튼
$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = T '저장하면 몇 초 안에 자동 적용됩니다. (언어는 즉시)' 'Applied automatically within seconds of saving.'
$lblHint.Location = New-Object System.Drawing.Point(16, 794)
$lblHint.Size = New-Object System.Drawing.Size(360, 22)
$lblHint.ForeColor = [System.Drawing.Color]::FromArgb(180, 90, 0)
$form.Controls.Add($lblHint)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = T '저장' 'Save'
$btnSave.Location = New-Object System.Drawing.Point(430, 788)
$btnSave.Size = New-Object System.Drawing.Size(96, 32)
$btnSave.BackColor = [System.Drawing.Color]::FromArgb(220, 240, 220)
$form.Controls.Add($btnSave)

$btnClose = New-Object System.Windows.Forms.Button
$btnClose.Text = T '닫기' 'Close'
$btnClose.Location = New-Object System.Drawing.Point(536, 788)
$btnClose.Size = New-Object System.Drawing.Size(96, 32)
$form.Controls.Add($btnClose)
$btnClose.Add_Click({ $form.Close() })

# 개발자 / 버전 표기
$lblAbout = New-Object System.Windows.Forms.Label
$lblAbout.Text = "$Version   |   " + (T '개발: 김설호' 'Developer: Kim Sulho') + '   |   jeremywrightkim@gmail.com'
$lblAbout.Location = New-Object System.Drawing.Point(16, 818)
$lblAbout.Size = New-Object System.Drawing.Size(400, 20)
$lblAbout.ForeColor = [System.Drawing.Color]::Gray
$form.Controls.Add($lblAbout)

# 표시 언어. 바꾸면 즉시 저장하고 창을 새 언어로 다시 연다.
# 알림 버튼과 기본 문구도 이 설정을 따른다.
$lblLang = New-Object System.Windows.Forms.Label
$lblLang.Text = 'Language'
$lblLang.Location = New-Object System.Drawing.Point(430, 830)
$lblLang.Size = New-Object System.Drawing.Size(80, 20)
$form.Controls.Add($lblLang)

$cmbLang = New-Object System.Windows.Forms.ComboBox
$cmbLang.Location = New-Object System.Drawing.Point(512, 827)
$cmbLang.Size = New-Object System.Drawing.Size(120, 24)
$cmbLang.DropDownStyle = 'DropDownList'
[void]$cmbLang.Items.AddRange(@('한국어', 'English'))
$cmbLang.SelectedIndex = if ($Lang -eq 'en') { 1 } else { 0 }
$form.Controls.Add($cmbLang)
$cmbLang.Add_SelectedIndexChanged({
    $newLang = if ($cmbLang.SelectedIndex -eq 1) { 'en' } else { 'ko' }
    if ($newLang -eq $script:Lang) { return }
    try { Save-Language $newLang } catch { }
    $script:Lang = $newLang
    $Script:Restart = $true
    $form.Close()
})

$btnSave.Add_Click({
    try {
        $s = Read-Settings
        if (-not $s.PSObject.Properties['hooks']) {
            $s | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([PSCustomObject]@{}) -Force
        }

        foreach ($pair in @(@{T=$tabNotif; E='Notification'}, @{T=$tabStop; E='Stop'})) {
            $c = $pair.T.Ctl
            $ev = $pair.E

            if (-not $c.On.Checked) {
                if ($s.hooks.PSObject.Properties[$ev]) { $s.hooks.PSObject.Properties.Remove($ev) }
                continue
            }

            $sndKey = @($Sounds.Keys)[$c.Snd.SelectedIndex]
            $cfg = @{
                Message  = $c.Msg.Text
                Title    = $c.Title.Text
                Scenario = $(if ($c.Stay.Checked) { 'reminder' } else { 'default' })
                Hero     = $(if ($c.Big.Checked) { $c.Hero.Text } else { '' })
                Logo     = $(if ($c.Small.Checked) { $c.Logo.Text } else { '' })
                Circle   = $c.Circle.Checked
                Sound    = $sndKey
                Loop     = $c.Loop.Checked
            }

            $matcher = ''
            if ($ev -eq 'Notification' -and $c.All -and -not $c.All.Checked) {
                $keys = @($NotifTypes.Keys)
                $sel = @()
                for ($i = 0; $i -lt $c.Cond.Items.Count; $i++) {
                    if ($c.Cond.GetItemChecked($i)) { $sel += $keys[$i] }
                }
                if ($sel.Count -gt 0) { $matcher = $sel -join '|' }
            }

            $entry = [PSCustomObject]@{
                matcher = $matcher
                hooks   = @([PSCustomObject]@{ type = 'command'; command = (Build-Command $cfg) })
            }
            $s.hooks | Add-Member -NotePropertyName $ev -NotePropertyValue @($entry) -Force
        }

        if ($s.hooks.PSObject.Properties.Count -eq 0) { $s.PSObject.Properties.Remove('hooks') }

        # 백업 후 저장. Claude Code는 BOM 없는 UTF-8 JSON을 기대한다.
        if (Test-Path $SettingsPath) {
            $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
            Copy-Item $SettingsPath "$SettingsPath.$stamp.bak" -Force
        }
        $json = $s | ConvertTo-Json -Depth 20
        [System.IO.File]::WriteAllText($SettingsPath, $json, [System.Text.UTF8Encoding]::new($false))
        $null = Get-Content $SettingsPath -Raw -Encoding UTF8 | ConvertFrom-Json

        [System.Windows.Forms.MessageBox]::Show(
            (T "저장했습니다.`n`n실행 중인 Claude Code에 몇 초 안에 자동 반영됩니다.`n반영되지 않으면 Claude Code를 재시작하세요." `
               "Saved.`n`nRunning Claude Code sessions pick this up within a few seconds.`nIf not, restart Claude Code."),
            (T '저장 완료' 'Saved'),'OK','Information') | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show((T '저장 실패' 'Save failed') + ":`n$($_.Exception.Message)",
            (T '오류' 'Error'),'OK','Error') | Out-Null
    }
})

[void]$form.ShowDialog()
$form.Dispose()
}
