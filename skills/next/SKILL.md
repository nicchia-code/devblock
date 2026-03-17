---
name: next
description: "Advance to the next feature in the DevBlock queue"
user_invocable: true
---

# /devblock:next — Avanza alla Prossima Feature

## REGOLE ASSOLUTE

- **DEVE** chiedere conferma via AskUserQuestion prima di avanzare.
- **VIETATO** invocare `/devblock:unfocus` autonomamente — e' distruttivo e resta user-only.
- **VIETATO** scrivere o modificare `.scope.json` direttamente.

## Flusso

### 1. Verifica stato

Leggi `.scope.json` e verifica:
- C'e' una sessione attiva?
- C'e' una feature corrente? In che fase e'?
- La coda ha feature rimanenti?

### 2. Mostra contesto

Se c'e' una feature corrente non completata:
- Mostra: "Feature corrente: {nome} (fase: {fase})"
- Avvisa: "Il controller verifichera' che i test passino prima di avanzare."

Se la feature corrente e' completata:
- Mostra: "Feature completata: {nome}"

Se la coda e' vuota:
- Mostra: "Coda vuota! Tutte le feature sono completate."
- Termina.

### 3. Mostra prossima feature

Mostra i dettagli della prossima feature in coda in formato tabella:
- Nome
- File implementazione
- File test
- Comando test

### 4. Esecuzione

Chiama via Bash:
```
.devblock/devblock-ctl.sh next
```

### 5. Risultato

**Se riesce:**
- Mostra la nuova feature attiva in tabella
- Informa che la fase gather e' attiva
- Inizia subito ad analizzare il contesto per la feature

**Se fallisce:**
- Mostra errore del controller
- Spiega cosa fare
