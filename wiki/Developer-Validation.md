# Developer Validation

The target shell is POSIX `/bin/sh` under BusyBox `ash`.

## Shell syntax checks

For touched shell scripts, run:

```sh
sh -n installer
sh -n AdGuardHome.sh
sh -n S99AdGuardHome
sh -n rc.func.AdGuardHome
```

## Optional ShellCheck

If ShellCheck is available outside the router:

```sh
shellcheck -s sh installer AdGuardHome.sh S99AdGuardHome rc.func.AdGuardHome
```

## Compatibility reminders

Avoid Bash-only features such as `[[ ... ]]`, arrays, here-strings, process substitution, `source`, and `pipefail`. Prefer quoted variables, `printf`, `case`, and POSIX command substitution.
