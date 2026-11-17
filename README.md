<div align="center">

# THORIUM
### Gamemode Roleplay para MTA:SA 1.6

*Un servidor de roleplay hecho desde cero: sin recursos prestados de otros gamemodes, sin atajos y con la seguridad pensada desde el primer commit.*

![MTA:SA](https://img.shields.io/badge/MTA%3ASA-1.6-e8590c?style=flat-square)
![Lua](https://img.shields.io/badge/Lua-5.1-2c2d72?style=flat-square&logo=lua&logoColor=white)
![MariaDB](https://img.shields.io/badge/MariaDB-10.4%2B-003545?style=flat-square&logo=mariadb&logoColor=white)
![Recursos](https://img.shields.io/badge/recursos-18-2f9e44?style=flat-square)
![Idioma](https://img.shields.io/badge/idioma-espa%C3%B1ol-c92a2a?style=flat-square)

</div>

---

## Qué es Thorium

Thorium es el gamemode de un servidor de roleplay en español para Multi Theft Auto: San Andreas. Cada sistema vive en su propio recurso `rp_*`, se comunica con los demás por exports y eventos, y guarda todo por **personaje** (no por cuenta), como se espera de un RP serio.

El objetivo no es juntar la mayor cantidad de features, sino que cada una esté bien hecha: interfaces propias en CEF y dx, validación completa en el servidor y una base de datos que se crea sola al arrancar.

## Lo que ya funciona

| Área | Qué tiene |
|---|---|
| **Cuenta** | Login y registro en CEF, contraseñas con bcrypt, límite de intentos, una sesión por cuenta, máximo 3 cuentas por serial y registro de accesos. |
| **Personajes** | 3 slots por cuenta, creación con vista previa del ped en vivo, skins por género y guardado periódico. |
| **Cabezas** | 78 cabezas personalizadas sobre el cuerpo de CJ para hombres, cargadas con `engineRequestModel`. |
| **Supervivencia** | Hambre, sed y energía por personaje; `/dormir` solo en interiores. |
| **Economía** | Dinero en mano, cuenta bancaria con historial de transacciones, cajeros (el retiro solo se hace en cajero) y tiendas con NPC. |
| **Inventario** | Inventario por personaje con catálogo de items (tecla `I`). |
| **Teléfono** | Notas, contactos, banco y *Fotogram* (red social con fotos tomadas en el juego). Tecla `P`. |
| **Propiedades** | Casas comprables con visita de un minuto, cierre y venta. |
| **Vehículos** | Vehículos con dueño persistentes, bloqueo con `L` o `/bloquear`. |
| **Concesionario** | Coutt and Schutz: stock al azar que rota cada 60 minutos, pago desde el banco y entrega segura. |
| **Interfaz** | HUD propio con minimapa giratorio (radar extraído del propio juego), notificaciones con sonido, scoreboard, nametags y sistema de IDs. |

## Arquitectura

```
                        ┌───────────────┐
                        │  rp_database  │  conexión única + schema automático
                        └───────┬───────┘
          ┌─────────────┬───────┴───────┬──────────────┐
     ┌────▼────┐  ┌─────▼───────┐ ┌─────▼──────┐ ┌─────▼─────┐
     │rp_login │→ │rp_characters│→│rp_inventory│ │  rp_bank  │ ...
     └─────────┘  └─────┬───────┘ └─────┬──────┘ └─────┬─────┘
     rp:onAccountLogin  │ rp:onCharacterSpawn          │
                  ┌─────▼───────┐          ┌───────────▼────────────┐
                  │ needs / hud │          │ phone · shops · houses │
                  └─────────────┘          │ vehicles · dealership  │
                                           └────────────────────────┘
```

- **Una conexión MySQL** compartida; los recursos la piden con `exports.rp_database:getConnection()`.
- **Eventos de ciclo de vida**: `rp:onAccountLogin` y `rp:onCharacterSpawn` encadenan el resto de sistemas.
- **Esquema autogestionado**: `schema.lua` ejecuta `CREATE TABLE IF NOT EXISTS` al iniciar. No hay que importar ningún `.sql`.
- **Sin funciones por exports** (MTA no lo permite): se usa `dbPoll(-1)` o eventos.

## Recursos

| Recurso | Responsabilidad |
|---|---|
| `rp_database` | Conexión y creación de tablas |
| `rp_login` | Autenticación (CEF + bcrypt) |
| `rp_characters` | Selección, creación y guardado de personajes |
| `rp_heads` | Cabezas personalizadas (modelos de terceros, ver créditos) |
| `bone_attach` | Pegar objetos a huesos de peds (de terceros) |
| `rp_notify` | Notificaciones, popups y burbujas |
| `rp_ids` | ID libre más bajo por jugador |
| `rp_scoreboard` · `rp_nametags` · `rp_hud` | Interfaz en pantalla |
| `rp_inventory` | Items por personaje |
| `rp_needs` | Hambre, sed, energía |
| `rp_shops` · `rp_bank` · `rp_dealership` | Economía |
| `rp_phone` | Teléfono con apps |
| `rp_rides` | App de viajes Vroom (conductores jugadores o IA) |
| `rp_properties` · `rp_vehicles` | Casas y vehículos |

Exports y comandos de cada recurso, en [`RECURSOS.md`](RECURSOS.md).

## Instalación

**Requisitos:** servidor MTA:SA 1.6 y MariaDB/MySQL 10.4+ (XAMPP sirve).

1. **Clona** el repo y copia su contenido sobre la carpeta `mods/deathmatch` de tu servidor (`resources/`, `mtaserver.conf`, `acl.xml`):
   ```bash
   git clone https://github.com/zThorium/MTA-SA-Roleplay-Gamemode-Thorium.git thorium
   ```
2. **Crea la base y su usuario** (sin permisos fuera de ella):
   ```sql
   CREATE DATABASE mtarp CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   CREATE USER 'mtarp'@'127.0.0.1' IDENTIFIED BY 'una-contraseña-larga';
   GRANT ALL PRIVILEGES ON mtarp.* TO 'mtarp'@'127.0.0.1';
   ```
3. **Configura las credenciales**:
   ```bash
   cp thorium/resources/[roleplay]/rp_database/config.example.lua thorium/resources/[roleplay]/rp_database/config.lua
   ```
   y edita la contraseña. `config.lua` está en `.gitignore`.
4. **Registra los recursos** en `mtaserver.conf`, en este orden (importa):
   ```xml
   <resource src="rp_database"   startup="1" protected="0" />
   <resource src="rp_notify"     startup="1" protected="0" />
   <resource src="rp_ids"        startup="1" protected="0" />
   <resource src="rp_login"      startup="1" protected="0" />
   <resource src="bone_attach"   startup="1" protected="0" />
   <resource src="rp_heads"      startup="1" protected="0" />
   <resource src="rp_characters" startup="1" protected="0" />
   <resource src="rp_needs"      startup="1" protected="0" />
   <resource src="rp_inventory"  startup="1" protected="0" />
   <resource src="rp_shops"      startup="1" protected="0" />
   <resource src="rp_bank"       startup="1" protected="0" />
   <resource src="rp_phone"      startup="1" protected="0" />
   <resource src="rp_properties" startup="1" protected="0" />
   <resource src="rp_vehicles"   startup="1" protected="0" />
   <resource src="rp_dealership" startup="1" protected="0" />
   <resource src="rp_nametags"   startup="1" protected="0" />
   <resource src="rp_scoreboard" startup="1" protected="0" />
   <resource src="rp_hud"        startup="1" protected="0" />
   ```
5. Genera `rp_hud/images/map.png` con `tools/RadarExtract.cs` (ver créditos) para el minimapa.
6. Arranca el servidor, entra, registra una cuenta y crea tu personaje.

### Administrador
Los comandos de admin (`/crearshop`, `/crearcasa`, `/dealer`...) exigen `accounts.admin_level >= 1`:
```sql
UPDATE accounts SET admin_level = 1 WHERE username = 'TuUsuario';
```

## Seguridad

- Toda validación se **repite en el servidor**; el cliente solo reenvía datos.
- Consultas **siempre parametrizadas** (`?`), nunca SQL concatenado.
- bcrypt asíncrono (`passwordHash` / `passwordVerify`) para no bloquear el servidor.
- Máximo 5 intentos fallidos → kick; 5 minutos para iniciar sesión.
- Chat bloqueado sin sesión; intentos registrados en `login_log`.
- Credenciales fuera del repo (`config.lua` ignorado).

## Hoja de ruta

- [ ] Verificar en juego las coordenadas de casas y concesionario
- [ ] Tono de piel de brazos según raza
- [ ] Trabajos y facciones
- [ ] Licencias y documentos
- [ ] Panel de administración

## Créditos y licencia

- **Cabezas (`rp_heads`)**: modelos y ajustes de **Aleks**, tomados de *Countryside-RP* y publicados por Neus. Su licencia exige dar crédito y **prohíbe venderlos**; esa restricción aplica a este repo mientras los incluya.
- **`bone_attach`**: **CrystalMV**.
- El mapa del radar de `rp_hud` (`images/map.png`) se genera a partir de tu propio `gta3.img` con `rp_hud/tools/RadarExtract.cs`; no se incluye porque son archivos de Rockstar.
- El resto del código es obra de **Thorium**. Grand Theft Auto: San Andreas es propiedad de Rockstar Games; este proyecto no está afiliado a Rockstar ni a MTA.

<div align="center"><sub>Hecho con paciencia, café y demasiadas horas en Grove Street.</sub></div>
