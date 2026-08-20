# Benchmarks

This directory will contain versioned benchmark fixtures, prompt templates, raw run metadata, and generated scoreboards.

Raw run output and generated scoreboards are ignored by Git until their schemas and provenance rules are established. This is deliberate: corpus manifests, configurations, schema versions, and curated summary scoreboards will be committed, while large or privacy-sensitive raw artifacts will use an explicitly selected artifact store or Git LFS. See the project README for the planned translation-only and end-to-end evaluation tracks.

The initial public-data baseline will evaluate FLEURS read speech and corresponding FLORES text where available. Every run must record the exact dataset revision, locale configuration, license, prompt version, model identity, and whether speech recognition and translation models were loaded concurrently. A smaller conversational set will cover code-switching, overlap, music, and disfluency that read speech does not represent.
