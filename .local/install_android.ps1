$ErrorActionPreference = 'Continue'
$dir = 'D:\dev\upmark\.local'
$log = Join-Path $dir 'android_install.log'
New-Item -ItemType Directory -Force -Path $dir, 'D:\android-sdk\cmdline-tools', 'D:\jdk17' | Out-Null
function Log($m) { Add-Content -Path $log -Value "$(Get-Date -Format HH:mm:ss) $m" }

Log '=== 安装开始 ==='

# ---------- JDK17 ----------
Log '下载 Temurin JDK17 ...'
curl.exe -sSL -o 'D:\jdk17\jdk.zip' 'https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse?project=jdk'
if (-not (Test-Path 'D:\jdk17\jdk.zip')) { Log 'JDK下载失败'; exit 1 }
Log '解压 JDK17 ...'
Expand-Archive 'D:\jdk17\jdk.zip' -DestinationPath 'D:\jdk17' -Force
$jdir = (Get-ChildItem 'D:\jdk17' -Directory | Where-Object Name -like 'jdk-*' | Select-Object -First 1).FullName
$env:JAVA_HOME = $jdir
[Environment]::SetEnvironmentVariable('JAVA_HOME', $jdir, 'User')
Log "JAVA_HOME = $jdir"

# ---------- Android cmdline-tools ----------
Log '下载 Android cmdline-tools ...'
curl.exe -sSL -o 'D:\android-sdk\tools.zip' 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip'
Expand-Archive 'D:\android-sdk\tools.zip' -DestinationPath 'D:\android-sdk\cmdline-tools' -Force
if (Test-Path 'D:\android-sdk\cmdline-tools\cmdline-tools') {
    Move-Item 'D:\android-sdk\cmdline-tools\cmdline-tools' 'D:\android-sdk\cmdline-tools\latest' -Force
}
$sdkmgr = 'D:\android-sdk\cmdline-tools\latest\bin\sdkmanager.bat'

# ---------- SDK组件 ----------
Log '安装 platform-tools / android-34 / build-tools（约600MB）...'
& $sdkmgr --sdk_root=D:\android-sdk --yes 'platform-tools' 'platforms;android-34' 'build-tools;34.0.0' 2>&1 | ForEach-Object { Log "  $_" }

# ---------- Licenses ----------
Log '接受全部 licenses ...'
1..40 | ForEach-Object { 'y' } | & $sdkmgr --sdk_root=D:\android-sdk --licenses 2>&1 | Out-Null

# ---------- 关联 Flutter ----------
Log 'flutter config --android-sdk ...'
$env:Path = 'D:\flutter\bin;' + $env:Path
& 'D:\flutter\bin\flutter.bat' config --android-sdk D:\android-sdk 2>&1 | ForEach-Object { Log "  $_" }
Log 'flutter doctor ...'
& 'D:\flutter\bin\flutter.bat' doctor 2>&1 | ForEach-Object { Log "  $_" }

'DONE' | Set-Content (Join-Path $dir 'android_install_done.txt')
Log '=== 全部完成 ==='
