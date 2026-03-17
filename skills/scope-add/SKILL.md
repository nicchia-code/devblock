---
name: scope-add
description: "Add a file to the current DevBlock scope (implementation or test)"
user_invocable: true
---

# /devblock:scope-add — Aggiungi File allo Scope

## REGOLE ASSOLUTE

- **VIETATO** invocare `/devblock:unfocus` autonomamente — e' distruttivo e resta user-only.
- **VIETATO** scrivere o modificare `.scope.json` direttamente.

## Argomenti

Questa skill accetta un argomento: il file da aggiungere.
- `/devblock:scope-add src/middleware/auth.ts` — path esatto
- `/devblock:scope-add src/middleware/*.ts` — glob pattern
- `/devblock:scope-add il file di validazione` — linguaggio naturale
- `/devblock:scope-add tests/auth.test.ts --test` — aggiunge come file test

## Flusso

### 1. Risolvi il file

A seconda dell'input:

**Path esatto** (contiene `/` o `.`):
- Verifica che il file esista o sia un path valido per un nuovo file
- Mostra il file risolto

**Glob pattern** (contiene `*` o `?`):
- Espandi con Glob
- Mostra i file trovati
- Chiedi all'utente quali aggiungere

**Linguaggio naturale** (tutto il resto):
- Cerca nel codebase con Glob/Grep
- Mostra i file candidati
- Chiedi all'utente quale aggiungere

### 2. Determina tipo

Determina se il file e' implementazione o test:
- Se l'utente ha specificato `--test`: e' un test file
- Se il path contiene pattern test (`test`, `spec`, `__tests__`): proponi come test file
- Altrimenti: proponi come file di implementazione

### 3. Mostra cosa cambiera'

Mostra in tabella:
- File: {path}
- Tipo: {implementazione/test}
- Scope attuale
- Nuovo scope

### 4. Esecuzione

Dopo aver mostrato il riepilogo, esegui via Bash:
```
.devblock/devblock-ctl.sh scope-add <file> [--test]
```

### 5. Risultato

**Se riesce:**
- Mostra conferma
- Mostra scope aggiornato

**Se fallisce:**
- File gia' in scope → informa l'utente
- .scope.json → informa che non puo' essere aggiunto
- Altro errore → mostra messaggio del controller
