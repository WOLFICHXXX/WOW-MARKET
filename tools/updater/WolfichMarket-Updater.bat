@echo off
chcp 65001 >nul
rem WolfichMarket: обновление аддона одним двойным кликом. Скачивает свежую версию с сайта и кладёт в папку AddOns.
rem Запуск с ключом /silent - без вопросов и окон (для автозапуска).
set "WM_SELF=%~f0"
set "WM_ARGS=%*"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s = [IO.File]::ReadAllText($env:WM_SELF, [Text.Encoding]::UTF8); $i = $s.IndexOf('#' + 'PSSTART'); Invoke-Expression $s.Substring($i)"
exit /b
#PSSTART
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$silent = ($env:WM_ARGS -match '/silent')
$site = 'https://wolfichxxx.github.io/WOW-MARKET/addon'
$cfgDir = Join-Path $env:APPDATA 'WolfichMarket'
$cfg = Join-Path $cfgDir 'addons-folder.txt'
New-Item -ItemType Directory -Force -Path $cfgDir | Out-Null

function Say($t, $c = 'Gray') { if (-not $silent) { Write-Host $t -ForegroundColor $c } }
function Done($code) { if (-not $silent) { Write-Host ''; Read-Host 'Нажмите Enter, чтобы закрыть' | Out-Null }; exit $code }

Say 'WolfichMarket - обновление аддона' 'Yellow'

# ---------- папка AddOns игры ----------
function Find-AddOns {
  $roots = @()
  foreach ($d in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Free -ne $null })) {
    $r = $d.Root
    $roots += @("$r", "${r}Program Files", "${r}Program Files (x86)", "${r}Games", "${r}Blizzard")
  }
  $found = @()
  foreach ($r in $roots) {
    $wow = Join-Path $r 'World of Warcraft'
    if (Test-Path $wow) {
      foreach ($flavor in (Get-ChildItem -Path $wow -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -like '_*_' })) {
        $a = Join-Path $flavor.FullName 'Interface\AddOns'
        if (Test-Path (Join-Path $flavor.FullName 'Interface')) { $found += $a }
      }
    }
  }
  return $found
}
$addons = $null
if (Test-Path $cfg) { $addons = (Get-Content $cfg -Raw).Trim() }
if (-not $addons -or -not (Test-Path (Split-Path $addons -Parent))) {
  $list = @(Find-AddOns)
  # сначала папка, где аддон уже стоит, потом WoW Forever
  $pick = $list | Where-Object { Test-Path (Join-Path $_ 'WolfichMarket') } | Select-Object -First 1
  if (-not $pick) { $pick = $list | Where-Object { $_ -match 'forever' } | Select-Object -First 1 }
  if (-not $pick -and $list.Count -eq 1) { $pick = $list[0] }
  if (-not $pick -and -not $silent) {
    Say 'Не нашёл папку игры. Укажите папку World of Warcraft\_forever_ (или папку Interface\AddOns).' 'Cyan'
    Add-Type -AssemblyName System.Windows.Forms
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = 'Папка игры WoW Forever (например World of Warcraft\_forever_) или её Interface\AddOns'
    if ($dlg.ShowDialog() -eq 'OK') {
      $p = $dlg.SelectedPath
      if ($p -match 'AddOns$') { $pick = $p } elseif (Test-Path (Join-Path $p 'Interface')) { $pick = Join-Path $p 'Interface\AddOns' } else { $pick = Join-Path $p 'Interface\AddOns' }
    }
  }
  if (-not $pick) { Say 'Папка игры не выбрана - обновлять некуда.' 'Red'; Done 1 }
  $addons = $pick
  Set-Content -Path $cfg -Value $addons -Encoding UTF8
}
New-Item -ItemType Directory -Force -Path $addons | Out-Null
Say "Папка аддонов: $addons"

# ---------- версии ----------
$toc = Join-Path $addons 'WolfichMarket\WolfichMarket.toc'
$have = $null
if (Test-Path $toc) { $m = Select-String -Path $toc -Pattern '^## Version:\s*(.+)$' | Select-Object -First 1; if ($m) { $have = $m.Matches[0].Groups[1].Value.Trim() } }
try { $latest = (Invoke-RestMethod -Uri "$site/version.json?t=$([DateTime]::UtcNow.Ticks)" -UseBasicParsing).version } catch { Say 'Не удалось связаться с сайтом. Проверьте интернет.' 'Red'; Done 1 }
Say ("Установлена: " + ($(if ($have) { $have } else { 'нет' })) + "   На сайте: $latest")
function VerNum($v) { $p = ($v -split '\.') + @('0','0','0'); return [int]$p[0] * 1000000 + [int]$p[1] * 1000 + [int]$p[2] }
if ($have -and (VerNum $have) -ge (VerNum $latest)) { Say 'Уже стоит последняя версия.' 'Green'; Done 0 }

# ---------- скачать и установить ----------
$tmp = Join-Path $env:TEMP "WolfichMarket-$latest.zip"
Say "Скачиваю версию $latest..."
Invoke-WebRequest -Uri "$site/WolfichMarket-$latest.zip" -OutFile $tmp -UseBasicParsing
$old = Join-Path $addons 'WolfichMarket'
if (Test-Path $old) { Remove-Item -Recurse -Force $old }   # настройки и цены хранятся в папке WTF - они не трогаются
Expand-Archive -Path $tmp -DestinationPath $addons -Force
Remove-Item $tmp -Force -ErrorAction SilentlyContinue
if (Test-Path $toc) { Say "Готово: WolfichMarket $latest установлен. Если игра запущена - напишите /reload." 'Green' } else { Say 'Что-то пошло не так: файлы аддона не появились.' 'Red'; Done 1 }

# ---------- автозапуск (спрашиваем один раз) ----------
$flag = Join-Path $cfgDir 'autostart-asked.txt'
if (-not $silent -and -not (Test-Path $flag)) {
  Set-Content -Path $flag -Value 'yes'
  $a = Read-Host 'Проверять обновления автоматически при входе в Windows? (y - да, n - нет)'
  if ($a -match '^\s*(y|yes|д|да|l)') {
    $startup = [Environment]::GetFolderPath('Startup')
    $lnk = Join-Path $startup 'WolfichMarket-Updater.lnk'
    $sh = New-Object -ComObject WScript.Shell
    $sc = $sh.CreateShortcut($lnk)
    $sc.TargetPath = $env:WM_SELF
    $sc.Arguments = '/silent'
    $sc.WindowStyle = 7
    $sc.Save()
    Say 'Готово: при входе в Windows аддон будет обновляться сам.' 'Green'
  }
}
Done 0
