# Applies app name, window title, size and icon to the generated Windows runner.
# Safe to run repeatedly.
$ErrorActionPreference = 'Stop'

function Replace-InFile($path, $pairs) {
  $text = Get-Content $path -Raw
  $orig = $text
  foreach ($p in $pairs) { $text = $text.Replace($p[0], $p[1]) }
  if ($text -ne $orig) { Set-Content -Path $path -Value $text -NoNewline -Encoding UTF8; Write-Host "Patched $path" }
}

Copy-Item installer/app_icon.ico windows/runner/resources/app_icon.ico -Force

Replace-InFile 'windows/CMakeLists.txt' @(
  ,@('set(BINARY_NAME "christman_site_progress")', 'set(BINARY_NAME "ChristmanSiteProgress")')
)

Replace-InFile 'windows/runner/main.cpp' @(
  @('window.Create(L"christman_site_progress"', 'window.Create(L"Christman Site Progress"'),
  @('Win32Window::Size size(1280, 720);', 'Win32Window::Size size(1440, 900);')
)

Replace-InFile 'windows/runner/Runner.rc' @(
  @('VALUE "CompanyName", "com.christman"', 'VALUE "CompanyName", "Rady Radwan"'),
  @('VALUE "FileDescription", "christman_site_progress"', 'VALUE "FileDescription", "Christman Site Progress"'),
  @('VALUE "InternalName", "christman_site_progress"', 'VALUE "InternalName", "ChristmanSiteProgress"'),
  @('VALUE "OriginalFilename", "christman_site_progress.exe"', 'VALUE "OriginalFilename", "ChristmanSiteProgress.exe"'),
  @('VALUE "ProductName", "christman_site_progress"', 'VALUE "ProductName", "Christman Site Progress"')
)
