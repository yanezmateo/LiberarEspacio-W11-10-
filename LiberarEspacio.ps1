<#
.SYNOPSIS
    Script integral para liberar espacio en disco.
    Combina limpieza de perfiles, Cleanmgr automatizado y explorador interactivo de carpetas.
#>

# 1. Solicitar permisos de administrador automaticamente
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Solicitando permisos de administrador..." -ForegroundColor Yellow
    try {
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    } catch {
        Write-Host "No se otorgaron los permisos. El script se cerrara." -ForegroundColor Red
        Start-Sleep -Seconds 3
    }
    exit
}

$Host.UI.RawUI.WindowTitle = "Herramienta Integral de Liberacion de Espacio"

# Funciones compartidas
function Get-FolderSizeFormatted($path) {
    try {
        $robo = robocopy $path "$env:TEMP\robo_dummy" /L /S /XJ /BYTES /NJH /NFL /NDL /R:0 /W:0
        $bytesLine = $robo | Where-Object { $_ -match '(?i)Bytes:\s+(\d+)' } | Select-Object -First 1
        if ($bytesLine -match '(?i)Bytes:\s+(\d+)') {
            $sizeMB = [double]$matches[1] / 1MB
            if ($sizeMB -ge 1024) {
                return "$([math]::Round($sizeMB / 1024, 2)) GB"
            } else {
                return "$([math]::Round($sizeMB, 2)) MB"
            }
        }
        return "0 MB"
    } catch {
        return "Desconocido"
    }
}

function Get-FolderSizeMB($path) {
    try {
        $robo = robocopy $path "$env:TEMP\robo_dummy" /L /S /XJ /BYTES /NJH /NFL /NDL /R:0 /W:0
        $bytesLine = $robo | Where-Object { $_ -match '(?i)Bytes:\s+(\d+)' } | Select-Object -First 1
        if ($bytesLine -match '(?i)Bytes:\s+(\d+)') {
            return [math]::Round([double]$matches[1] / 1MB, 2)
        }
        return 0
    } catch {
        return 0
    }
}

function Get-CFreeSpaceBytes {
    $drive = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='C:'"
    return [double]$drive.FreeSpace
}

function Format-Bytes($bytes) {
    if ($bytes -ge 1GB) {
        return "$([math]::Round($bytes / 1GB, 2)) GB"
    } else {
        return "$([math]::Round($bytes / 1MB, 2)) MB"
    }
}

function Limpiar-Perfiles {
    Write-Host "`n--- LIMPIEZA DE PERFILES DE USUARIO ---" -ForegroundColor Cyan
    Write-Host "Buscando perfiles de usuario y calculando espacio..."
    $profiles = Get-CimInstance -Class Win32_UserProfile | Where-Object { $_.Special -eq $false -and $_.Loaded -eq $false }

    $userList = @()
    $counter = 1
    $totalProfiles = @($profiles).Count

    foreach ($profile in $profiles) {
        $username = ($profile.LocalPath -split '\\')[-1]
        
        $percent = 0
        if ($totalProfiles -gt 0) { $percent = [math]::Round((($counter - 1) / $totalProfiles) * 100) }
        Write-Progress -Activity "Analizando perfiles inactivos ($counter de $totalProfiles)" -Status "Calculando tamano de: $username" -PercentComplete $percent
        
        $sizeStr = Get-FolderSizeFormatted $profile.LocalPath
        
        $lastUse = "Desconocido"
        $ntuser = Join-Path $profile.LocalPath "NTUSER.DAT"
        if (Test-Path -LiteralPath $ntuser) {
            $lastUse = (Get-Item -LiteralPath $ntuser -Force).LastWriteTime.ToString("dd/MM/yyyy HH:mm")
        } elseif ($profile.LastUseTime) {
            $lastUse = $profile.LastUseTime.ToString("dd/MM/yyyy HH:mm")
        }

        $userList += [PSCustomObject]@{
            Id = $counter
            Username = $username
            LocalPath = $profile.LocalPath
            Size = $sizeStr
            LastUse = $lastUse
            Profile = $profile
        }
        $counter++
    }
    Write-Progress -Activity "Analizando perfiles inactivos" -Completed

    if ($userList.Count -eq 0) {
        Write-Host "No se encontraron perfiles inactivos para eliminar." -ForegroundColor Yellow
        Read-Host "`nPresione Enter para continuar"
        return $false
    }

    $formatString = "{0,-5} | {1,-20} | {2,-10} | {3,-16} | {4,-25}"
    Write-Host "`n"
    Write-Host ($formatString -f "ID", "Usuario", "Tamano", "Ultimo Uso", "Ruta") -ForegroundColor Cyan
    Write-Host ("-" * 85) -ForegroundColor Cyan

    foreach ($user in $userList) {
        Write-Host ($formatString -f "[$($user.Id)]", $user.Username, $user.Size, $user.LastUse, $user.LocalPath)
    }

    Write-Host "`nOpciones de Seleccion:" -ForegroundColor Cyan
    Write-Host "  [Numeros]  Eliminar usuarios especificos (Ej: 1, 3, 4)"
    Write-Host "  [T]        Eliminar TODOS los usuarios 'im' (luego podra excluir numeros)"
    Write-Host "  [S]        Cancelar y volver al menu principal"

    $validSelection = $false
    while (-not $validSelection) {
        $selection = Read-Host "`nIndique su opcion (Numeros, 'T' o 'S')"
        if ([string]::IsNullOrWhiteSpace($selection)) { continue }
        if ($selection -match '(?i)^s$') { return $false }

        $profilesToDelete = @()

        if ($selection -match '(?i)^t$') {
            $allImUsers = $userList | Where-Object { $_.Username -match '(?i)^im.*' }
            if ($allImUsers.Count -eq 0) { Write-Host "No se encontraron perfiles 'im'." -ForegroundColor Yellow; continue }
            
            Write-Host "`nSe han preseleccionado los siguientes usuarios 'im':" -ForegroundColor Magenta
            $allImUsers | ForEach-Object { Write-Host " - [$($_.Id)] $($_.Username)" }
            $exclusions = Read-Host "`nDesea EXCLUIR alguno? (Ingrese IDs separados por coma, o deje vacio para borrar todos)"
            
            if ([string]::IsNullOrWhiteSpace($exclusions)) {
                $profilesToDelete = $allImUsers
                $validSelection = $true
            } else {
                $excludedIds = $exclusions -split ',' | ForEach-Object { $_.Trim() }
                $profilesToDelete = $allImUsers | Where-Object { $excludedIds -notcontains $_.Id.ToString() }
                $validSelection = $true
            }
        } else {
            $selectedIds = $selection -split ',' | ForEach-Object { $_.Trim() }
            $validSelection = $true 
            foreach ($id in $selectedIds) {
                if ($id -match '^\d+$') {
                    $match = $userList | Where-Object { $_.Id -eq [int]$id }
                    if ($match) { $profilesToDelete += $match } 
                    else { Write-Host "Numero $id no existe en la lista." -ForegroundColor Red; $validSelection = $false }
                } else { Write-Host "'$id' entrada invalida." -ForegroundColor Red; $validSelection = $false }
            }
        }
    }

    if ($profilesToDelete.Count -gt 0) {
        $profilesToDelete = @($profilesToDelete | Sort-Object -Unique -Property Id)

        Write-Host "`nSe ELIMINARAN permanentemente los siguientes perfiles:" -ForegroundColor Red
        $totalMB = 0
        foreach ($user in $profilesToDelete) {
            Write-Host " - [$($user.Id)] $($user.Username) ($($user.Size))"
            if ($user.Size -match '([\d\.]+)\s+GB') { $totalMB += [double]$matches[1] * 1024 } 
            elseif ($user.Size -match '([\d\.]+)\s+MB') { $totalMB += [double]$matches[1] }
        }
        
        $totalStr = if ($totalMB -ge 1024) { "$([math]::Round($totalMB / 1024, 2)) GB" } else { "$([math]::Round($totalMB, 2)) MB" }
        Write-Host "Espacio estimado a liberar: aprox. $totalStr" -ForegroundColor Cyan
        
        Write-Host "`nEsta seguro? (S/N): " -NoNewline
        $confirm = [System.Console]::ReadKey($true).KeyChar
        Write-Host $confirm
        if ($confirm -match '(?i)^s$') {
            Write-Host ""
            $delCounter = 1
            $totalToDel = $profilesToDelete.Count
            foreach ($user in $profilesToDelete) {
                $percent = [math]::Round((($delCounter - 1) / $totalToDel) * 100)
                Write-Progress -Activity "Eliminando perfiles ($delCounter de $totalToDel)" -Status "Borrando: $($user.Username)" -PercentComplete $percent
                try {
                    Write-Host "Borrando perfil de $($user.Username)... " -NoNewline
                    Remove-CimInstance -InputObject $user.Profile -ErrorAction Stop
                    Write-Host "HECHO" -ForegroundColor Green
                } catch {
                    Write-Host "ERROR ($($_.Exception.Message))" -ForegroundColor Red
                }
                $delCounter++
            }
            Write-Progress -Activity "Eliminando perfiles" -Completed
            Write-Host "Limpieza de perfiles finalizada." -ForegroundColor Green
            return $true
        } else { return $false }
    }
    return $false
}

function Ejecutar-Cleanmgr {
    Write-Host "`n--- LIMPIADOR DE WINDOWS (Archivos Temporales y Updates) ---" -ForegroundColor Cyan
    Write-Host "Configurando el limpiador de disco para seleccionar todas las opciones de forma automatica..."
    
    $volumeCaches = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
    $caches = Get-ChildItem -Path $volumeCaches -ErrorAction SilentlyContinue
    
    foreach ($cache in $caches) {
        try {
            Set-ItemProperty -Path $cache.PSPath -Name "StateFlags0099" -Value 2 -Type DWord -ErrorAction SilentlyContinue
        } catch { }
    }
    
    Write-Host "Ejecutando Cleanmgr.exe... (Aparecera una ventana nativa de Windows que se cerrara sola al terminar)" -ForegroundColor Green
    Write-Host "Espere a que el limpiador finalice su trabajo..."
    Start-Process -FilePath "cleanmgr.exe" -ArgumentList "/sagerun:99" -Wait
    Write-Host "Limpieza de disco de Windows completada." -ForegroundColor Green
}

function Analizar-CarpetasPesadas {
    $currentPath = "ESTE EQUIPO"
    
    while ($true) {
        Clear-Host
        Write-Host "--- EXPLORADOR DE ESPACIO EN DISCO ---" -ForegroundColor Cyan
        Write-Host "Navega por las carpetas para encontrar exactamente que elementos estan ocupando espacio." -ForegroundColor Yellow
        
        $files = @()
        $folders = @()
        $folderStats = @()
        $total = 0

        if ($currentPath -eq "ESTE EQUIPO") {
            Write-Host "`n[Ubicacion actual: MIS DISCOS]" -ForegroundColor Magenta
            $discos = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3")
            foreach ($disco in $discos) {
                $label = if ($disco.DeviceID -eq "C:") { "(Sistema)" } else { "(Datos)" }
                $usadoMB = [math]::Round(($disco.Size - $disco.FreeSpace) / 1MB, 2)
                $folderStats += [PSCustomObject]@{
                    Id = 0
                    Ruta = "$($disco.DeviceID)\"
                    Nombre = "[DISCO] $($disco.DeviceID)\ $label"
                    Tamano = if ($usadoMB -ge 1024) { "$([math]::Round($usadoMB / 1024, 2)) GB" } else { "$([math]::Round($usadoMB, 2)) MB" }
                    TamanoNum = $usadoMB
                    EsCarpeta = $true
                }
            }
        } elseif ($currentPath -eq "C:\") {
            Write-Host "`n[Ubicacion actual: RAIZ DE C:\ Y USUARIOS]" -ForegroundColor Magenta
            # Omitimos carpetas del sistema intocables y ReparsePoints
            $folders += Get-ChildItem -Path "C:\" -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
                $_.Attributes -notmatch "ReparsePoint" -and $_.Name -notmatch '(?i)^(Windows|Archivos de programa|Program Files.*|Users)$'
            }
            $folders += Get-ChildItem -Path "C:\Users" -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
                $_.Attributes -notmatch "ReparsePoint"
            }
            $files = Get-ChildItem -Path "C:\" -File -Force -ErrorAction SilentlyContinue | Where-Object {
                $_.Extension -notmatch '(?i)^\.sys$' -and $_.Name -notmatch '(?i)^dumpstack\.log.*$'
            }
        } else {
            Write-Host "`n[Ubicacion actual: $currentPath]" -ForegroundColor Magenta
            $folders = Get-ChildItem -Path $currentPath -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
                $_.Attributes -notmatch "ReparsePoint"
            }
            $files = Get-ChildItem -Path $currentPath -File -Force -ErrorAction SilentlyContinue | Where-Object {
                $_.Extension -notmatch '(?i)^\.sys$'
            }
        }

        $total = $folders.Count
        $counter = 1

        if ($total -gt 0) {
            foreach ($folder in $folders) {
                $percent = [math]::Round((($counter - 1) / $total) * 100)
                Write-Progress -Activity "Analizando espacio en disco" -Status "Escaneando: $($folder.Name)" -PercentComplete $percent
                
                $sizeMB = Get-FolderSizeMB $folder.FullName
                if ($sizeMB -gt 50 -or $currentPath -ne "C:\") { 
                    $folderStats += [PSCustomObject]@{
                        Id = 0
                        Ruta = $folder.FullName
                        Nombre = "[CARPETA] $($folder.Name)"
                        Tamano = if ($sizeMB -ge 1024) { "$([math]::Round($sizeMB / 1024, 2)) GB" } else { "$([math]::Round($sizeMB, 2)) MB" }
                        TamanoNum = $sizeMB
                        EsCarpeta = $true
                    }
                }
                $counter++
            }
            Write-Progress -Activity "Analizando espacio en disco" -Completed
        }

        # Detectar archivos pesados
        if ($files.Count -gt 0) {
            foreach ($file in $files) {
                $sizeMB = [math]::Round($file.Length / 1MB, 2)
                if ($sizeMB -gt 50) { 
                    $folderStats += [PSCustomObject]@{
                        Id = 0
                        Ruta = $file.FullName
                        Nombre = "[ARCHIVO] $($file.Name)"
                        Tamano = if ($sizeMB -ge 1024) { "$([math]::Round($sizeMB / 1024, 2)) GB" } else { "$([math]::Round($sizeMB, 2)) MB" }
                        TamanoNum = $sizeMB
                        EsCarpeta = $false
                    }
                }
            }
        }

        $folderStats = @($folderStats | Sort-Object TamanoNum -Descending)
        
        $i = 1
        foreach ($f in $folderStats) {
            $f.Id = $i
            $i++
        }

        if ($folderStats.Count -eq 0) {
            Write-Host "No se encontraron elementos pesados (> 50 MB) aqui." -ForegroundColor Yellow
        } else {
            $formatString = "{0,-5} | {1,-60} | {2,-15}"
            Write-Host "`n"
            Write-Host ($formatString -f "ID", "Nombre del Elemento", "Tamano") -ForegroundColor Cyan
            Write-Host ("-" * 85) -ForegroundColor Cyan
            $rowColorToggle = $true
            foreach ($f in $folderStats) {
                if ($f.Nombre -match "^\[DISCO\]") {
                    $color = if ($rowColorToggle) { "Green" } else { "DarkGreen" }
                } elseif ($f.EsCarpeta) {
                    $color = if ($rowColorToggle) { "White" } else { "DarkGray" }
                } else {
                    $color = if ($rowColorToggle) { "Yellow" } else { "DarkYellow" }
                }
                Write-Host ($formatString -f "[$($f.Id)]", $f.Nombre, $f.Tamano) -ForegroundColor $color
                $rowColorToggle = -not $rowColorToggle
            }
        }

        Write-Host "`nOpciones:" -ForegroundColor Cyan
        if ($folderStats.Count -gt 0) { 
            Write-Host "  [Numero]   Entrar a un elemento" 
            Write-Host "  [E Numero] Eliminar un elemento (Ej: E 2)"
        }
        if ($currentPath -ne "ESTE EQUIPO") { Write-Host "  [A]        Atras (Subir un nivel)" }
        Write-Host "  [S]        Salir al Menu Principal"

        $valid = $false
        while (-not $valid) {
            $opcion = Read-Host "`nIndique su opcion"
            if ([string]::IsNullOrWhiteSpace($opcion)) { continue }
            
            if ($opcion -match '(?i)^s$') {
                return
            } elseif ($opcion -match '(?i)^a$' -and $currentPath -ne "ESTE EQUIPO") {
                if ($currentPath -match '^[A-Z]:\\?$') {
                    $currentPath = "ESTE EQUIPO"
                } else {
                    $parent = Split-Path $currentPath
                    if ($parent -match '(?i)^C:\\Users$') {
                        $currentPath = "C:\"
                    } elseif ($parent -match '^[A-Z]:\\?$') {
                        $parentLetter = $parent.Substring(0,2)
                        $currentPath = "$parentLetter\"
                    } else {
                        $currentPath = $parent
                    }
                }
                $valid = $true
            } elseif ($opcion -match '(?i)^e\s+(\d+)$') {
                $id = [int]$matches[1]
                $match = $folderStats | Where-Object { $_.Id -eq $id }
                if ($match) {
                    if ($match.Nombre -match "^\[DISCO\]") {
                        Write-Host "`n[!] No puedes formatear un disco entero desde aqui." -ForegroundColor Red
                        continue
                    }
                    $tipoStr = if ($match.EsCarpeta) { "la CARPETA" } else { "el ARCHIVO" }
                    Write-Host "`nEsta seguro de eliminar permanentemente $tipoStr '$($match.Ruta)'? (S/N): " -NoNewline
                    $conf = [System.Console]::ReadKey($true).KeyChar
                    Write-Host $conf
                    if ($conf -match '(?i)^s$') {
                        if ($match.EsCarpeta -and $match.Ruta -match '(?i)^C:\\Users\\[^\\]+$') {
                            Write-Host "`nADVERTENCIA: Esta intentando borrar la carpeta de un perfil de usuario directamente." -ForegroundColor Red
                            Write-Host "Esto dejara residuos en el registro. Se recomienda encarecidamente usar la OPCION 1 del menu principal." -ForegroundColor Red
                            Write-Host "Desea forzar el borrado de todos modos? (S/N): " -NoNewline
                            $conf2 = [System.Console]::ReadKey($true).KeyChar
                            Write-Host $conf2
                            if ($conf2 -notmatch '(?i)^s$') {
                                Write-Host "`nEliminacion cancelada." -ForegroundColor Yellow
                                continue
                            }
                            Write-Host ""
                        }
                        
                        Write-Host "`nEliminando... " -ForegroundColor Yellow
                        try {
                            Remove-Item -Path $match.Ruta -Recurse -Force -ErrorAction Stop
                            Write-Host "Eliminado con exito." -ForegroundColor Green
                        } catch {
                            Write-Host "Error parcial o total al eliminar: $($_.Exception.Message)" -ForegroundColor Red
                            Write-Host "(Puede que algunos archivos esten actualmente en uso por Windows)" -ForegroundColor Red
                        }
                        Read-Host "`nPresione Enter para actualizar la vista"
                        $valid = $true
                    } else {
                        Write-Host "`nEliminacion cancelada." -ForegroundColor Yellow
                    }
                } else {
                    Write-Host "Numero no valido." -ForegroundColor Red
                }
            } elseif ($opcion -match '^\d+$') {
                $match = $folderStats | Where-Object { $_.Id -eq [int]$opcion }
                if ($match) {
                    if ($match.EsCarpeta) {
                        $currentPath = $match.Ruta
                        $valid = $true
                    } else {
                        Write-Host "`nNo puedes entrar a un archivo. Usa 'E $($match.Id)' si quieres borrarlo." -ForegroundColor Red
                    }
                } else {
                    Write-Host "Numero no valido." -ForegroundColor Red
                }
            } else {
                Write-Host "Opcion no valida." -ForegroundColor Red
            }
        }
    }
}

function Vaciar-Papeleras {
    Write-Host "`n--- VACIADO RAPIDO (Papelera y Temp) ---" -ForegroundColor Cyan
    
    Write-Host "Vaciando Papelera de reciclaje de todos los usuarios en el disco..."
    Remove-Item -Path "C:\`$Recycle.Bin\*" -Recurse -Force -ErrorAction SilentlyContinue
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    
    Write-Host "Borrando temporales de sistema y de todos los usuarios..."
    $tempPaths = @(
        "C:\Windows\Temp\*",
        "C:\Users\*\AppData\Local\Temp\*"
    )
    foreach ($ruta in $tempPaths) {
        Get-ChildItem -Path $ruta -Force -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Stop
            } catch {
                # Ignorar archivos en uso
            }
        }
    }
    
    Write-Host "Limpiando cache de descargas trabadas de Windows Update..."
    Stop-Service -Name "wuauserv" -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Service -Name "wuauserv" -ErrorAction SilentlyContinue
    
    Write-Host "Hecho." -ForegroundColor Green
}

# Bucle del Menu Principal
while ($true) {
    Clear-Host
    $discos = @(Get-CimInstance Win32_LogicalDisk -Filter "DriveType=3")

    Write-Host "`n=========================================================" -ForegroundColor DarkCyan
    Write-Host "         MANTENIMIENTO Y LIBERACION DE ESPACIO           " -ForegroundColor Cyan
    Write-Host "=========================================================" -ForegroundColor DarkCyan
    
    foreach ($disco in $discos) {
        $espacioLibre = Format-Bytes $disco.FreeSpace
        $espacioTotal = Format-Bytes $disco.Size
        $label = if ($disco.DeviceID -eq "C:") { "(Sistema)" } else { "(Datos)  " }
        Write-Host "   Disco $($disco.DeviceID) $label -> Libre: " -ForegroundColor Gray -NoNewline
        Write-Host "$espacioLibre" -ForegroundColor Green -NoNewline
        Write-Host " / Total: $espacioTotal" -ForegroundColor Gray
    }
    
    if ($discos.Count -eq 1) {
        Write-Host "   (No se detectaron otros volumenes locales)" -ForegroundColor DarkGray
    }
    
    Write-Host "=========================================================`n" -ForegroundColor DarkCyan
    
    Write-Host "  [ 1 ] " -ForegroundColor Cyan -NoNewline
    Write-Host "Eliminar Perfiles de Usuario" -ForegroundColor White
    
    Write-Host "`n  [ 2 ] " -ForegroundColor Cyan -NoNewline
    Write-Host "Ejecutar Limpiador de Windows" -ForegroundColor White
    Write-Host "        (Cleanmgr automatizado - Todo seleccionado)" -ForegroundColor DarkGray

    Write-Host "`n  [ 3 ] " -ForegroundColor Cyan -NoNewline
    Write-Host "Explorador Interactivo de Espacio" -ForegroundColor White
    Write-Host "        (Navega y encuentra archivos/carpetas pesadas)" -ForegroundColor DarkGray

    Write-Host "`n  [ 4 ] " -ForegroundColor Cyan -NoNewline
    Write-Host "Vaciado Rapido" -ForegroundColor White
    Write-Host "        (Papelera de reciclaje y Temps GLOBALES)" -ForegroundColor DarkGray

    Write-Host "`n  [ S ] " -ForegroundColor Red -NoNewline
    Write-Host "Salir" -ForegroundColor Gray
    Write-Host "`n=========================================================" -ForegroundColor DarkCyan
    
    $opcion = Read-Host "`n  Seleccione una opcion"
    
    if ([string]::IsNullOrWhiteSpace($opcion)) { continue }
    
    # Calcular antes
    $bytesAntes = Get-CFreeSpaceBytes
    $accionRealizada = $false
    $pausar = $false

    switch -Regex ($opcion) {
        '^1$' { 
            $res = Limpiar-Perfiles
            $accionRealizada = $res
            $pausar = $res
        }
        '^2$' { Ejecutar-Cleanmgr; $accionRealizada = $true; $pausar = $true }
        '^3$' { Analizar-CarpetasPesadas; $pausar = $false } # No pausar al volver del explorador
        '^4$' { Vaciar-Papeleras; $accionRealizada = $true; $pausar = $true }
        '(?i)^s$' { 
            Write-Host "`nCerrando herramienta..." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
            exit 
        }
        default { Write-Host "Opcion no valida." -ForegroundColor Red; $pausar = $true }
    }
    
    # Mostrar resultados solo para acciones que borran cosas
    if ($accionRealizada) {
        $bytesDespues = Get-CFreeSpaceBytes
        $liberado = $bytesDespues - $bytesAntes
        
        if ($liberado -gt 0) {
            Write-Host "`n[+] EXITO: Se han liberado " -ForegroundColor Green -NoNewline
            Write-Host "$(Format-Bytes $liberado)" -ForegroundColor Magenta -NoNewline
            Write-Host " de espacio en tu disco C:\ en esta accion." -ForegroundColor Green
        } elseif ($liberado -lt 0) {
            Write-Host "`n[-] No se aprecia liberacion significante." -ForegroundColor DarkGray
        } else {
            Write-Host "`n[=] No se pudo liberar espacio (archivos en uso o ya estaba todo limpio)." -ForegroundColor DarkGray
        }
    }
    
    if ($pausar) {
        Read-Host "`nPresione Enter para volver al menu principal"
    }
}
