# Kai Ollama archive import

## Guarantee

The full-history importer sends no archive content to OpenAI or another cloud
model. It preflights Ollama and `qwen3:8b`, calls brain extraction with
`allowCloudFallback: false`, and stops resumably if local inference becomes
unavailable. Each checkpoint records `provider: ollama` and `paidTokens: 0`.

The older saved-memory text box remains a separate, clearly labeled cloud
importer. It is not used by the full-history path.

## Run

1. Start Ollama and ensure `qwen3:8b` is installed.
2. Export ChatGPT data and unzip it locally.
3. In Kai, open Brain, then the memory-import button.
4. Under **FULL HISTORY — OLLAMA ONLY**, select `conversations.json`.
5. Review the local-token estimate.
6. Import the richest ten conversations first, inspect the resulting graph, and
   then choose **Import / resume all**.

Pause waits for the current conversation to finish and checkpoint before
stopping. Re-selecting the same export and resuming skips all completed hashes.

## Data boundaries

- The raw export remains in the user-selected local file.
- Obvious task chatter is rejected deterministically before inference.
- Selected conversations are capped before local inference.
- The knowledge graph stores extracted claims with archive source handles.
- Bounded evidence capsules store short excerpts for auditability but are marked
  `livePromptEligible: false`.
- Historical assistant text is marked `historical_voice_only`; it cannot become
  a factual claim about the user or present-day Kai merely because an older
  assistant wrote it.

The normal conversation prompt never receives the archive. Future retrieval may
select a small number of relevant claims or capsules under its own token budget.
