# DevBlock — Scope Enforcement

DevBlock **automatically enforces** scope and TDD phase constraints via `scope-guard.sh`, a PreToolUse hook that runs on every Edit, Write, MultiEdit, and Bash call.

## Fasi

| Fase | Editabili | Validazione transizione |
|------|-----------|------------------------|
| gather | Nessuno | — |
| test | Solo test | — |
| run | Nessuno | Test devono FALLIRE |
| implement | Solo impl | — |
| **fix-tests** | **Solo test** | **Correggere test da implement/retest** |
| retest | Nessuno | Test devono PASSARE |
| review | Nessuno | — |
| done | Nessuno | — |

## Rules (when `.scope.json` exists)

1. **`.scope.json` is read-only** — never edit it directly; use `devblock-ctl.sh` (via skills like `/devblock:phase`, `/devblock:next`, `/devblock:scope-add`).
2. **No active feature → edits blocked** — start from a plan or use `/devblock:next`.
3. **Files must be in scope** — only files listed in `current.files` or `current.tests` can be edited. If a file is missing, suggest `/devblock:scope-add`.
4. **Phase locking** — see table above. Only the allowed file types are writable in each phase.
5. **File-modifying Bash commands blocked** — redirects (`>`), `sed -i`, `rm`, `mv`, `cp`, etc. are denied during an active session. Use Edit/Write tools instead (they are scope-checked). Test runners are whitelisted.

## When `.scope.json` does not exist

All restrictions are off — the hook allows everything.

## Regola transizioni

L'agent **DEVE SEMPRE**, prima di ogni cambio fase:
1. **Spiegare** cosa sta facendo e perche'
2. **Chiedere conferma** all'utente (via AskUserQuestion)

Questo vale per OGNI transizione, sia in avanti che indietro.

## Transizioni valide

```
gather → test        (nessuna validazione)
test → run           (nessuna validazione)
run → implement      (test DEVONO FALLIRE + warning se errori non-assertion)
implement → retest   (nessuna validazione)
implement → fix-tests (salva return_to=implement)
retest → fix-tests   (salva return_to=retest)
fix-tests → implement (solo se return_to=implement)
fix-tests → retest   (solo se return_to=retest)
retest → review      (test DEVONO PASSARE)
review → done        (nessuna validazione, utente conferma)
review → gather      (review KO, ricomincia)
*qualsiasi* → gather (backward, utente conferma, auto-stash da implement/fix-tests)
*qualsiasi* → test   (backward, utente conferma, auto-stash da implement/fix-tests)
```

## Loop Autonomo

Dopo l'init, l'agent guida il ciclo attraverso le 7 fasi:

1. **gather** — Leggi codice, capisci contesto. Poi chiedi: "Ho analizzato X, Y, Z. Posso passare a scrivere i test?"
2. **test** — Scrivi test. Poi chiedi: "Test scritti per X. Posso eseguirli?"
3. **run** — Esegui test command. Il ctl valida che falliscano. Poi chiedi: "I test falliscono correttamente. Posso implementare?"
4. **implement** — Scrivi implementazione. Poi chiedi: "Implementazione completata. Posso rieseguire i test?"
5. **retest** — Esegui test. Il ctl valida che passino. Poi chiedi: "Tutti i test passano. Posso fare la review?"
6. **review** — Revisione read-only. Se KO: chiedi di tornare a gather. Se OK: chiedi di marcare done.
7. **done** — Stampa riepilogo tabellare. Proponi commit. Se coda non vuota, chiedi di avanzare.

## Entry plan-based

Quando il hook PostToolUse su ExitPlanMode inietta il messaggio, Claude:
- Chiede "Vuoi sviluppare con DevBlock?"
- Se si': legge il piano, estrae feature come JSON
- Mostra TABELLA: Feature | File Impl | File Test | Test Command
- Utente accetta o modifica → `devblock-ctl.sh init`

## Tornare indietro

L'agent puo' proporre di tornare a qualsiasi fase precedente, ma **DEVE** chiedere conferma e spiegare il motivo.

## Tabelle

Usare tabelle per: recap sessione, status, transizioni, review findings, done summary.

## Rollback on mistakes

Se fai un errore durante una fase TDD:
1. Rollbacka i file con `git checkout -- <file>`
2. Informa l'utente cosa e' successo
3. Riprendi dalla fase corretta — mai avanzare fase per coprire un errore

## Fase fix-tests

La fase `fix-tests` e' una sotto-fase che sblocca i file di test **senza perdere il lavoro di implementazione**. Si usa quando durante `implement` o `retest` si scopre che i test hanno bug o assumono un'API shape sbagliata.

- Raggiungibile solo da `implement` e `retest`
- Permette di editare solo file test (come la fase `test`)
- Il campo `current.return_to` in `.scope.json` traccia la fase di provenienza
- Si puo' tornare solo alla fase da cui si e' entrati

## Regole fase test

Durante la fase `test`, i file di test devono contenere SOLO:
- Test cases e asserzioni
- Fixture e setup minimali
- Import necessari

**Vietato** scrivere nei file di test:
- Logica di business o utility che implementino la feature
- Codice che farebbe passare i test senza implementazione reale

## Auto-stash

Quando si esegue una backward transition (`*→gather`, `*→test`) dalla fase `implement` o `fix-tests`, il controller esegue automaticamente `git stash push`. L'utente puo' fare `git stash pop` dopo aver corretto i test.

## /devblock:unfocus MAI autonomo

Solo l'utente puo' invocare `/devblock:unfocus`. Mai invocarlo autonomamente.

## Important

Never tell the user that scope enforcement doesn't exist. It does, via hooks. If an edit is denied, explain the rule and suggest the appropriate skill to resolve it.
