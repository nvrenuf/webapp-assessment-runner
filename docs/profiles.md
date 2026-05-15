# Profiles and Depth Controls

Profiles define the default assessment depth for phases that support tunable rate, timing, target selection, or template scope. They provide a repeatable way to adjust coverage while keeping safety controls visible.

## Available profiles

| Profile | Intent | Operator expectation |
| --- | --- | --- |
| `safe` | Lowest-impact baseline for production-friendly unauthenticated checks. | Use first for most official runs. Keeps rates low and target sets narrow. |
| `balanced` | Moderate baseline with slightly faster timing while retaining low-impact limits. | Use when safe results are clean and the engagement allows more coverage. |
| `deep` | Expanded coverage for approved windows. | Still avoids intrusive behavior, but runs longer and may include more targets such as both base and login URLs. |
| `maintenance` | Recurring checks of known targets with operator approval. | May be broader or faster than normal profiles. Treat as requiring explicit approval and a suitable maintenance window. |

`maintenance` does not mean unrestricted testing. Any intrusive active scan, broad discovery, fuzzing, brute force, DoS, race testing, or authenticated workflow abuse still requires explicit written authorization and a defined window.

## Example profile settings

The repository profile files live under `config/profiles/`. Current example defaults are:

| Phase/tool | `safe` | `balanced` | `deep` | `maintenance` |
| --- | --- | --- | --- | --- |
| Nikto timing | `NIKTO_PAUSE=5`, `NIKTO_MAXTIME=2h` | `NIKTO_PAUSE=2`, `NIKTO_MAXTIME=2h` | `NIKTO_PAUSE=1`, `NIKTO_MAXTIME=4h` | `NIKTO_PAUSE=1`, `NIKTO_MAXTIME=6h` |
| Nikto target mode | `login` | `login` | `both` | `both` |
| Nmap ports | `443` | `443` | `80,443` | `80,443` |
| Nmap pacing | `NMAP_MAX_RATE=1`, `NMAP_SCAN_DELAY=2s` | `NMAP_MAX_RATE=2`, `NMAP_SCAN_DELAY=1s` | `NMAP_MAX_RATE=3`, `NMAP_SCAN_DELAY=500ms` | `NMAP_MAX_RATE=5`, `NMAP_SCAN_DELAY=250ms` |
| Nuclei rate/concurrency | `NUCLEI_RATE=1`, `NUCLEI_CONCURRENCY=1` | `NUCLEI_RATE=1`, `NUCLEI_CONCURRENCY=1` | `NUCLEI_RATE=2`, `NUCLEI_CONCURRENCY=1` | `NUCLEI_RATE=3`, `NUCLEI_CONCURRENCY=2` |
| Nuclei tags | `exposure,misconfig,cors,csp,headers,tls,ssl` | `exposure,misconfig,cors,csp,headers,tls,ssl` | `exposure,misconfig,cors,csp,headers,tls,ssl,tech` | `exposure,misconfig,cors,csp,headers,tls,ssl,tech,token,cloud` |
| Nuclei excluded tags | `fuzz,bruteforce,dos,race,intrusive` | `fuzz,bruteforce,dos,race,intrusive` | `fuzz,bruteforce,dos,race,intrusive` | `dos,race,intrusive` |

## How profiles are applied

A workspace records its selected profile in `config/target.env`. Phase scripts load the workspace target config and then the matching repository profile file, such as `config/profiles/safe.env`.

Use profiles to set baseline behavior, then review the phase output to confirm which values were actually applied. Many phases write effective settings into summaries or status files.

## Overriding profile values

Preferred override methods:

1. Edit the workspace configuration for the specific run when the override is engagement-specific.
2. Create or adjust a profile file under `config/profiles/` when the change should be reusable.
3. Record the reason for the override in the run notes or report narrative.

Keep overrides narrow and explicit. For example, changing `NMAP_PORTS=80,443` for a known web target is different from approving broad port discovery. Broader discovery should be scoped and documented as a separate activity.

## When to increase depth

Increase scope or depth only when:

- The rules of engagement allow it.
- The target owner understands the additional traffic and timing.
- The safe profile has completed without operational concerns.
- The operator has reviewed prior evidence and understands what additional coverage is needed.
- A maintenance or lower-traffic window is available for longer-running checks.

Do not increase depth merely to convert scanner output into report findings. Confirmation should come from Phase 7 direct validation and Phase 9 normalization, not from running louder scanners.
