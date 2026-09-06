<#
.SYNOPSIS
    야간 수집 배치를 Windows 작업 스케줄러에 등록·해제·확인한다.

.DESCRIPTION
    매일 23:00에 `python -m job_matching_bot.crawling.nightly`를 저장소 루트에서 돌린다.
    출력은 job_matching_bot/artifacts/nightly/log/<날짜>.log 에 남는다.
    가상환경(playdata_venv)의 python을 쓴다. Pinecone·OpenAI 패키지가 거기 있다.

    노트북이 꺼져 있으면 그 밤은 건너뛴다(다음 밤에 이어서 받는다). 배터리 상태에서도 돌고,
    켜져 있기만 하면 잠자기에서 깨워서 돈다.

.EXAMPLE
    .\job_matching_bot\crawling\schedule_nightly.ps1 -Register
    .\job_matching_bot\crawling\schedule_nightly.ps1 -Status
    .\job_matching_bot\crawling\schedule_nightly.ps1 -RunNow
    .\job_matching_bot\crawling\schedule_nightly.ps1 -Unregister
#>
[CmdletBinding()]
param(
    [switch]$Register,
    [switch]$Unregister,
    [switch]$Status,
    [switch]$RunNow,
    [string]$At = "23:00",
    [string]$TaskName = "JobMatchingBot Nightly"
)

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$python = Join-Path $repoRoot "playdata_venv\Scripts\python.exe"
$logDir = Join-Path $repoRoot "job_matching_bot\artifacts\nightly\log"

if ($Register) {
    if (-not (Test-Path $python)) {
        Write-Error "가상환경 python이 없습니다: $python"
        exit 1
    }
    New-Item -ItemType Directory -Force $logDir | Out-Null
    # cmd로 감싸서 표준 출력·오류를 날짜별 로그로 보낸다.
    $command = "`"$python`" -m job_matching_bot.crawling.nightly >> `"$logDir\%DATE:~0,10%.log`" 2>&1"
    $action = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c $command" -WorkingDirectory $repoRoot
    $trigger = New-ScheduledTaskTrigger -Daily -At $At
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -WakeToRun -StartWhenAvailable `
        -ExecutionTimeLimit (New-TimeSpan -Hours 8) `
        -MultipleInstances IgnoreNew
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    Write-Host "등록: '$TaskName' 매일 $At · 로그 $logDir"
}

if ($Unregister) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "해제: '$TaskName'"
}

if ($RunNow) {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "시작: '$TaskName' (로그 $logDir)"
}

if ($Status -or -not ($Register -or $Unregister -or $RunNow)) {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($null -eq $task) {
        Write-Host "'$TaskName' 은 등록돼 있지 않습니다. -Register 로 등록하세요."
        exit 0
    }
    $info = Get-ScheduledTaskInfo -TaskName $TaskName
    Write-Host "작업: $TaskName ($($task.State))"
    Write-Host "  다음 실행: $($info.NextRunTime)"
    Write-Host "  마지막 실행: $($info.LastRunTime) (결과 코드 $($info.LastTaskResult))"
    $latest = Get-ChildItem $logDir -Filter *.log -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    if ($latest) { Write-Host "  최근 로그: $($latest.FullName)" }
}
