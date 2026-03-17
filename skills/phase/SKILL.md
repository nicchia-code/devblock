---
name: phase
description: "Transition DevBlock phase (gather→test→run→implement→retest→review→done) with validation"
user_invocable: true
---

# /devblock:phase — Transizione Fase

## REGOLE ASSOLUTE

- **DEVE** spiegare cosa sta facendo e chiedere conferma via AskUserQuestion prima di ogni transizione.
- **VIETATO** invocare `/devblock:unfocus` autonomamente — e' distruttivo e resta user-only.
- **VIETATO** scrivere o modificare `.scope.json` direttamente.

## Argomenti

Questa skill accetta un argomento: la fase target.
- `/devblock:phase test` — da gather a test
- `/devblock:phase run` — da test a run
- `/devblock:phase implement` — da run a implement
- `/devblock:phase retest` — da implement a retest
- `/devblock:phase review` — da retest a review
- `/devblock:phase done` — da review a done
- `/devblock:phase gather` — backward a gather (da qualsiasi fase)
- `/devblock:phase test` — backward a test (da qualsiasi fase)

## Flusso

### 1. Verifica stato corrente

Leggi `.scope.json` e mostra:
- Feature corrente
- Fase attuale
- Fase richiesta
- Cosa comporta la transizione

### 2. Tabella transizioni

| Da → A | Significato | Validazione |
|--------|------------|-------------|
| gather → test | Contesto analizzato, si scrivono i test | — |
| test → run | Test scritti, si eseguono | — |
| run → implement | Test falliscono, si implementa | Test DEVONO FALLIRE |
| implement → retest | Implementazione fatta, si rieseguono i test | — |
| retest → review | Test passano, si revisiona | Test DEVONO PASSARE |
| review → done | Review OK, feature completa | — |
| review → gather | Review KO, ricomincia | — |
| * → gather | Backward esplicito | Conferma utente |
| * → test | Backward esplicito | Conferma utente |

### 3. Conferma

L'agent **DEVE SEMPRE** chiedere conferma via AskUserQuestion prima di eseguire la transizione, spiegando:
- Cosa ha fatto nella fase corrente
- Perche' vuole avanzare (o tornare indietro)
- Cosa succedera' nella fase target

### 4. Revisione Codice Mock/Stub (solo per target = done)

Questo step si attiva **solo** quando la fase target e' `done`.

1. Leggi `current.files` da `.scope.json` (file di implementazione, **NON** test)
2. Lancia un **Agent** (subagent_type: `Explore`) che legge tutti i file di implementazione e cerca:
   - Valori di ritorno hardcoded
   - Commenti `TODO`, `FIXME`, `HACK`, `XXX`
   - Dati placeholder/fake nel codice di produzione
   - Oggetti mock o funzioni stub fuori dai test
   - Implementazioni reali commentate sostituite con mock
   - Funzioni vuote o con implementazione minima

3. **Se trovati mock/stub:**
   - Presenta i risultati in formato tabella: file, riga, descrizione
   - Per ogni rilevamento suggerisci un prompt correttivo
   - Chiedi via AskUserQuestion: "Trovato codice mock/stub residuo. Vuoi correggere prima di completare? (correggi / procedi comunque)"
   - Se **correggi**: termina il flusso
   - Se **procedi comunque**: continua

4. **Se nessun mock/stub trovato:** conferma brevemente e prosegui

### 5. Esecuzione

Solo dopo conferma dell'utente, chiama via Bash:
```
.devblock/devblock-ctl.sh phase <target>
```

Il controller:
- Esegue i test indipendentemente
- Valida il risultato
- Aggiorna `.scope.json` solo se la validazione passa

### 6. Rollback in caso di errore

Se durante una fase si verifica un errore:
1. **Identifica i file coinvolti**
2. **Rollbacka le modifiche** con `git checkout -- <file>`
3. **Informa l'utente**
4. **Riprendi dalla fase corretta**

### 7. Gestione risultato

**Se la transizione riesce:**
- Mostra la nuova fase
- Spiega cosa puo' fare l'utente ora

**Se la transizione fallisce:**
- Mostra il messaggio di errore del controller
- Spiega cosa fare

### 8. Transizione a DONE — Atomic Commit

Quando la fase target e' `done` e la transizione riesce:

1. Proponi un commit con messaggio descrittivo (tipo convenzionale)
2. Mostra quali file verranno committati (SOLO i file in scope)
3. Chiedi conferma del messaggio di commit via AskUserQuestion
4. Se l'utente conferma: stage i file in scope, crea il commit
5. Se la coda non e' vuota: invoca `/devblock:next` via Skill tool
6. Se la coda e' vuota: "Tutte le feature completate!"
