<#
.SYNOPSIS
    Script para eliminar perfiles de usuario.
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

$Host.UI.RawUI.WindowTitle = "Limpieza de Perfiles de Usuario"

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "   LIMPIEZA DE PERFILES DE USUARIO (SIN RASTROS) " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host ""

# Funcion para obtener el tamano de la carpeta rapidamente
function Get-FolderSizeFormatted($path) {
    try {
        # Usamos robocopy porque es la forma mas rapida en Windows, saltea uniones (/XJ) 
        # y no falla devolviendo 0 MB como lo hace FSO por problemas de permisos ocultos.
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

# Buscar perfiles
Write-Host "Buscando perfiles de usuario y calculando espacio..."
$profiles = Get-CimInstance -Class Win32_UserProfile | Where-Object { $_.Special -eq $false -and $_.Loaded -eq $false }

$userList = @()
$counter = 1
$totalProfiles = @($profiles).Count

foreach ($profile in $profiles) {
    $username = ($profile.LocalPath -split '\\')[-1]
    
    # --- BARRA DE PROGRESO ---
    $percent = 0
    if ($totalProfiles -gt 0) {
        $percent = [math]::Round((($counter - 1) / $totalProfiles) * 100)
    }
    Write-Progress -Activity "Analizando perfiles inactivos ($counter de $totalProfiles)" -Status "Calculando tamano de: $username" -PercentComplete $percent
    
    # Calcular tamano
    $sizeStr = Get-FolderSizeFormatted $profile.LocalPath
    
    # Obtener fecha de ultimo uso leyendo el registro local del usuario (muy preciso)
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

# Limpiar barra de progreso
Write-Progress -Activity "Analizando perfiles inactivos ($counter de $totalProfiles)" -Completed

if ($userList.Count -eq 0) {
    Write-Host "`nNo se encontraron perfiles inactivos para eliminar." -ForegroundColor Yellow
    Write-Host "(Nota: Los perfiles actualmente en uso o protegidos no se listan)." -ForegroundColor DarkGray
    Read-Host "`nPresione Enter para salir"
    exit
}

# 3. Mostrar la lista en la consola
Write-Host "`nPerfiles disponibles para eliminar:`n" -ForegroundColor Green

# Crear un formato de tabla
$formatString = "{0,-5} | {1,-20} | {2,-10} | {3,-16} | {4,-25}"
Write-Host ($formatString -f "ID", "Usuario", "Tamano", "Ultimo Uso", "Ruta") -ForegroundColor Cyan
Write-Host ("-" * 85) -ForegroundColor Cyan

foreach ($user in $userList) {
    Write-Host ($formatString -f "[$($user.Id)]", $user.Username, $user.Size, $user.LastUse, $user.LocalPath)
}

Write-Host "`nOpciones de Seleccion:" -ForegroundColor Cyan
Write-Host "  [Numeros]  Eliminar usuarios especificos (Ej: 1, 3, 4)"
Write-Host "  [T]        Eliminar TODOS los usuarios 'im' (luego podra excluir numeros)"
Write-Host "  [S]        Salir sin hacer nada"

$validSelection = $false
while (-not $validSelection) {
    $selection = Read-Host "`nIndique su opcion (Numeros, 'T' o 'S')"
    
    if ([string]::IsNullOrWhiteSpace($selection)) {
        continue
    }

    if ($selection -match '(?i)^s$') {
        Write-Host "`nOperacion cancelada." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        exit
    }

    $profilesToDelete = @()

    if ($selection -match '(?i)^t$') {
        # El usuario quiere borrar los 'im'
        $allImUsers = $userList | Where-Object { $_.Username -match '(?i)^im.*' }
        if ($allImUsers.Count -eq 0) {
            Write-Host "No se encontraron perfiles que empiecen con 'im'." -ForegroundColor Yellow
            continue
        }
        
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
        # El usuario ingreso numeros
        $selectedIds = $selection -split ',' | ForEach-Object { $_.Trim() }
        $validSelection = $true 
        foreach ($id in $selectedIds) {
            if ($id -match '^\d+$') {
                $match = $userList | Where-Object { $_.Id -eq [int]$id }
                if ($match) {
                    $profilesToDelete += $match
                } else {
                    Write-Host "El numero $id no esta en la lista." -ForegroundColor Red
                    $validSelection = $false
                }
            } else {
                Write-Host "'$id' no es una entrada valida." -ForegroundColor Red
                $validSelection = $false
            }
        }
    }
}

if ($profilesToDelete.Count -gt 0) {
    # Eliminar posibles duplicados basados en el ID para evitar el bug de PSCustomObject
    $profilesToDelete = @($profilesToDelete | Sort-Object -Unique -Property Id)

    Write-Host "`nSe ELIMINARAN permanentemente los siguientes perfiles:" -ForegroundColor Red
    $totalMB = 0
    
    foreach ($user in $profilesToDelete) {
        Write-Host " - [$($user.Id)] $($user.Username) ($($user.Size))"
        if ($user.Size -match '([\d\.]+)\s+GB') {
            $totalMB += [double]$matches[1] * 1024
        } elseif ($user.Size -match '([\d\.]+)\s+MB') {
            $totalMB += [double]$matches[1]
        }
    }
    
    if ($totalMB -ge 1024) {
        $totalStr = "$([math]::Round($totalMB / 1024, 2)) GB"
    } else {
        $totalStr = "$([math]::Round($totalMB, 2)) MB"
    }
    
    Write-Host "Espacio total a liberar: aprox. $totalStr" -ForegroundColor Cyan
    
    $confirm = Read-Host "`nEsta seguro? (S/N)"
    if ($confirm -match '(?i)^s$') {
        Write-Host ""
        $delCounter = 1
        $totalToDel = $profilesToDelete.Count
        
        foreach ($user in $profilesToDelete) {
            $percent = [math]::Round((($delCounter - 1) / $totalToDel) * 100)
            Write-Progress -Activity "Eliminando perfiles ($delCounter de $totalToDel)" -Status "Borrando usuario: $($user.Username)" -PercentComplete $percent
            
            try {
                Write-Host "Borrando perfil de $($user.Username)... " -NoNewline
                Remove-CimInstance -InputObject $user.Profile -ErrorAction Stop
                Write-Host "HECHO" -ForegroundColor Green
            } catch {
                Write-Host "ERROR" -ForegroundColor Red
                Write-Host "  Detalle: $($_.Exception.Message)" -ForegroundColor Red
            }
            $delCounter++
        }
        
        Write-Progress -Activity "Eliminando perfiles" -Completed
        Write-Host "`nLimpieza finalizada." -ForegroundColor Green
    } else {
        Write-Host "`nOperacion cancelada." -ForegroundColor Yellow
    }
} else {
    Write-Host "`nNo se selecciono ningun perfil valido para eliminar." -ForegroundColor Yellow
}

Read-Host "`nPresione Enter para cerrar"
