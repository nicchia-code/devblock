---
name: unfocus
description: "Close the current DevBlock session and remove scope constraints"
user_invocable: true
---

# /devblock:unfocus — Chiudi Sessione DevBlock

## REGOLE ASSOLUTE

- **VIETATO** invocare `/devblock:unfocus` autonomamente. Suggerisci SEMPRE il comando all'utente e aspetta che lo digiti.
- **VIETATO** scrivere o modificare `.scope.json` direttamente.
- **VIETATO** procedere senza conferma esplicita dell'utente.

## Flusso

### 1. Verifica sessione

Controlla se `.scope.json` esiste. Se non esiste:
- Informa: "Nessuna sessione DevBlock attiva."
- Termina.

### 2. Mostra stato corrente

Leggi `.scope.json` e mostra in tabella:
- Feature corrente (nome e fase)
- Numero di feature in coda
- File non committati in scope (usa `git status --porcelain` sui file in `current.files` e `current.tests`)

### 3. Avviso lavoro in corso

Se c'e' una feature attiva con fase diversa da `done`, oppure la coda non e' vuota, avvisa chiaramente:
- "**Attenzione:** c'e' lavoro in corso. Chiudere la sessione perdera' lo stato della feature corrente e della coda."

### 4. Offri commit (opzionale)

Se ci sono file modificati in scope:
- Chiedi via AskUserQuestion: "Ci sono file modificati in scope. Vuoi fare un commit prima di chiudere la sessione? (si / no)"
- Se **si**: esegui il commit dei file in scope
- Se **no**: prosegui senza commit

### 5. Conferma chiusura

Chiedi conferma esplicita via AskUserQuestion:
"Confermi di voler chiudere la sessione DevBlock? Questo rimuovera' `.scope.json` e disabilitera' tutti i vincoli di scope."

Se l'utente non conferma, termina senza fare nulla.

### 6. Opzione uninstall completo

Dopo la conferma, chiedi via AskUserQuestion:
"Vuoi anche rimuovere la directory `.devblock/` (uninstall completo)? (si / no)"

- Se **si**: esegui con `--full`
- Se **no**: esegui senza `--full`

### 7. Esecuzione

Solo dopo conferma dell'utente, chiama via Bash:

Per chiusura normale:
```
.devblock/devblock-ctl.sh unfocus
```

Per uninstall completo:
```
.devblock/devblock-ctl.sh unfocus --full
```

### 8. Conferma risultato

**Se riesce:**
- Mostra il messaggio di conferma dal controller
- Se chiusura normale: "Sessione chiusa. I file `.devblock/` sono ancora presenti. Crea un nuovo piano con /plan per ricominciare."
- Se uninstall completo: "Sessione chiusa e DevBlock disinstallato. Usa `/devblock:install` per reinstallare."

**Se fallisce:**
- Mostra l'errore del controller
