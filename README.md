## DBISAM dbsrvr.exe

A recompiled DBISAM `dbsrvr.exe` program w/ the TDBISAMDatabase 'Trigger' (listener) implementation 
capabilities for listening to A2-Softway DBISAM-based tables (tuples) and a simple JSON parser

## Repository GitHub deploy key location 

File path: `C:\Users\Administrador\.ssh`
Public key: `id_server.pub`

Command used: `ssh-keygen -t ed25519 -f id_server`

## Rad Studio project settings

#### Delphi compiler settings:

Find: Options -> Delphi Compiler -> Search Path 

Add: 
1. `C:\Program Files (x86)\DBISAM 4 VCL-TRIAL\RAD Studio 13 (Delphi Win32)\code\source`
2. `C:\Program Files (x86)\DBISAM 4 VCL-TRIAL\RAD Studio 13 (Delphi Win32)\utilcomps`
3. `C:\Program Files (x86)\DBISAM 4 VCL-TRIAL\RAD Studio 13 (Delphi Win32)\code` (not backed-up)

#### Runtime packages

From here: `C:\Program Files (x86)\DBISAM 4 VCL-TRIAL\RAD Studio 13 (Delphi Win32)\code`

Add:
1. `dbisamd.dcp`
2. `dbisamr.dcp`

## DBISAM programs (files installed)

1. `DBISAM 4 ADD`: contains the `srvadmin.exe` for managing DBISAM connections
2. `DBISAM 4 ODBC-TRIAL`: contains the source code of the win32 dbsrvr.exe 
3. `DBISAM 4 VCL-TRIAL`: contains the Rad Studio 13 plugin (Delphi win32) w/ additional libraries used by the compiler

## Additional scenarios to consider

1. Aware of the remote credentials and the file path associated with the database; the latter is hardcoded when compiling the `dbsrvr.exe`
2. The `Server Administration Utility (32-bits)` or `srvadmin.exe` is required for the initial setup. The default credentials are: `Admin` and `DBAdmin` as the password

## Credits
[David Lares S](https://davidlares.com)

## License
[MIT](https://opensource.org/licenses/MIT)
