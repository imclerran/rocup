# rocup feature matrix

| Capability                                                  | macOS/Linux (`rocup`) | Windows (`rocup.ps1`) |
|-------------------------------------------------------------|:---------------------:|:---------------------:|
| `latest` — install/activate newest nightly                  | yes                   | yes                   |
| `<hash>` — install/activate a specific nightly              | yes                   | yes                   |
| `+N` / `-N` — step through the nightly timeline             | yes                   | yes                   |
| `list` — show installed versions                            | yes                   | yes                   |
| `remove <ver>` — delete a version                           | yes                   | yes                   |
| `prune <N>` — keep N most recent nightlies                  | yes                   | yes                   |
| `<dir>` — register a local Roc build directory              | yes                   | yes                   |
| `local` — activate newest registered local build            | yes                   | yes                   |
| `alpha4` — install the alpha4-rolling release               | yes                   | no (no Windows binary) |
| `<file>` — register a single roc binary file                | yes                   | no (junctions are dir-only) |
| Cross-volume local builds                                   | yes                   | no (NTFS junctions require same volume) |
| Standalone `roc_language_server` binary dispatch            | yes                   | no (always uses `roc experimental-lsp`) |
| Optional `gh` CLI for GitHub API                            | yes                   | yes                   |

## When this matrix changes

- Adding a command to one side without the other will fail CI's `test/drift-check.sh`.
- If a divergence is intentional, update both this matrix AND the `KNOWN_BASH_ONLY` / `KNOWN_PS_ONLY` constants in `test/drift-check.sh`.
