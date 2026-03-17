---
name: status
description: "Show current DevBlock session status: feature, phase, scope, queue"
user_invocable: true
---

# /devblock:status — Dashboard Stato

## REGOLE ASSOLUTE

- **VIETATO** invocare `/devblock:unfocus` autonomamente — e' distruttivo e resta user-only.
- **VIETATO** scrivere o modificare `.scope.json` direttamente.
- Questa skill e' **read-only**.

## Flusso

### 1. Controlla sessione

Se `.scope.json` non esiste:
- Mostra: "Nessuna sessione DevBlock attiva. Crea un piano con /plan e approva per iniziare."
- Termina.

### 2. Leggi stato

Chiama `.devblock/devblock-ctl.sh status` via Bash per ottenere lo stato corrente.

### 3. Mostra dashboard

Formatta l'output in una dashboard con tabelle:

```
┌─ DEVBLOCK SESSION ──────────────────────┐
│ Feature: {nome feature}                  │
│ Phase:   {emoji} {PHASE} ({descrizione}) │
│                                          │
│ Implementation files:                    │
│   {icon} {file1}                         │
│   {icon} {file2}                         │
│                                          │
│ Test files:                              │
│   {icon} {test1}                         │
│                                          │
│ Test cmd: {test_command}                 │
│                                          │
│ Queue: {n} features remaining            │
│   ○ {feature1}                           │
│                                          │
│ Completed: {n}                           │
│   ● {completed1}                         │
└──────────────────────────────────────────┘
```

### Icone per fase

| Fase | Emoji | File impl | File test |
|------|-------|-----------|-----------|
| gather | 🔍 | 🔒 locked | 🔒 locked |
| test | 🔴 | 🔒 locked | ✏️ writable |
| run | 🏃 | 🔒 locked | 🔒 locked |
| implement | 🟢 | ✏️ writable | 🔒 locked |
| fix-tests | 🔧 | 🔒 locked | ✏️ writable |
| retest | 🏃 | 🔒 locked | 🔒 locked |
| review | 🔵 | 🔒 locked | 🔒 locked |
| done | ✅ | 🔒 locked | 🔒 locked |

### Se nessuna feature corrente ma coda non vuota

- "Nessuna feature in lavorazione"
- Coda rimanente
- Feature completate
- Suggerisci: "Usa /devblock:next per iniziare la prossima feature"

### Se nessuna feature corrente e coda vuota

- "Sessione completata!"
- Lista feature completate
