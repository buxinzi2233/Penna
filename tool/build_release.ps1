# 重新打包正式版,并在桌面放一个快捷方式。
# 用法(在项目根目录):  pwsh tool/build_release.ps1
#
# 项目路径里有中文时 Flutter 的正式版编译会失败,所以这里临时把上一级文件夹
# 映射成一个纯英文盘符再编译。项目搬到纯英文路径后,这段映射可以删掉。
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$drive = 'P:'
if (Get-Process penna -ErrorAction SilentlyContinue) {
  throw 'Penna 正在运行,程序文件被占用。请先关掉它再打包。'
}
if (Test-Path "$drive\") { throw "$drive 盘符已被占用,请改脚本里的 `$drive" }

subst $drive (Split-Path $root -Parent)
try {
  Set-Location "$drive\$(Split-Path $root -Leaf)"
  flutter clean | Out-Null
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw '编译失败,见上方输出' }
} finally {
  Set-Location $root
  subst $drive /D
  # 这份缓存里记着临时盘符的路径,留着会让之后的 flutter test 崩溃。
  $stale = Join-Path $root '.dart_tool\hooks_runner'
  if (Test-Path $stale) { Remove-Item -Recurse -Force $stale -Confirm:$false }
}

$exe = Join-Path $root 'build\windows\x64\runner\Release\penna.exe'
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Penna 羽毛笔.lnk'
$shortcut = (New-Object -ComObject WScript.Shell).CreateShortcut($lnk)
$shortcut.TargetPath = $exe
$shortcut.WorkingDirectory = Split-Path $exe
$shortcut.Description = 'Penna 羽毛笔 - 文生图提示词工作台'
$shortcut.Save()
"已更新: $lnk"
