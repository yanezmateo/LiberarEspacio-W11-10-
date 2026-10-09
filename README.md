# 🧹 Liberador de Espacio Interactivo (Windows 10/11)

Una herramienta de grado empresarial desarrollada en PowerShell, diseñada para limpiar el sistema operativo a profundidad, automatizar mantenimientos repetitivos y visualizar interactivamente qué archivos o carpetas están ocupando más espacio en el disco.

## ✨ Características Principales

El script despliega un menú interactivo que calcula en tiempo real el espacio disponible y ofrece 4 módulos principales:

### 1. 👥 Eliminación de Perfiles de Usuario
Analiza todos los perfiles guardados a través del proveedor WMI (`Win32_UserProfile`), filtrando inteligentemente las cuentas del dominio que comienzan con "im". 
- Permite limpiar equipos compartidos con extrema rapidez.
- Incluye validaciones cruzadas para evitar el borrado del perfil activo o de cuentas esenciales del sistema.
- Interfaz interactiva que permite exclusiones por ID para mantener los perfiles que sí importan.

### 2. 🪟 Limpiador de Windows (Cleanmgr) Automatizado
Automatiza el proceso de limpieza nativo de Windows configurando el registro de forma temporal (`StateFlags0099` a `2`).
- Ejecuta `cleanmgr.exe /sagerun:99` seleccionando de fondo todas las opciones (incluyendo la eliminación de respaldos gigantes de Windows Update y cachés de DirectX) sin requerir interacción manual.

### 3. 🔍 Explorador Interactivo de Espacio (Avanzado)
Una herramienta de navegación por consola construida desde cero. Inicia en un menú raíz que detecta automáticamente todos los volúmenes del equipo (C:, D:, etc.) y su espacio utilizado.
- Navegación rápida mediante comandos numéricos para entrar en las carpetas.
- Eliminación segura de archivos pesados o carpetas completas usando comandos simples (Ej: `E 2`).
- **Bloqueos de seguridad (Guiderails):** Oculta e impide totalmente la interacción con archivos críticos de Windows (`.sys`, `hiberfil.sys`, `pagefile.sys`, etc.) para evitar que alguien corrompa el sistema operativo por accidente.
- **UI Zebra-Striping:** Diseño de alto contraste que intercala filas con colores (Blanco/Gris para carpetas, Amarillo/Amarillo Oscuro para archivos) para una fácil lectura en la terminal.

### 4. 🗑️ Vaciado Global Rápido
- Purgado "agresivo" que destruye la Papelera de Reciclaje de **todos los usuarios** de la máquina de golpe.
- Recorre en bucle y borra tanto los temporales de sistema (`C:\Windows\Temp`) como la carpeta de Local AppData de **todos los perfiles** (`C:\Users\*\AppData\Local\Temp`).
- Detiene los servicios de Windows Update y elimina la caché de descargas trabadas (`SoftwareDistribution\Download`) que suelen devorar Gigabytes de forma oculta.

## 🚀 Uso y Requisitos

1. Ejecutar PowerShell (se recomienda usarlo siempre como Administrador).
2. Asegúrate de tener los permisos de ejecución de scripts habilitados.
3. Ejecutar:
   ```powershell
   .\LiberarEspacio.ps1
   ```
*(Nota: El script incluye un fragmento de auto-elevación que solicitará credenciales de Administrador en caso de que se haya ejecutado como un usuario regular).*

---
**Desarrollado para mantenimientos rápidos y precisos en infraestructuras Windows 10/11.**
