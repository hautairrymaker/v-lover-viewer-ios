# Voice subtitles

Verified baseline: commit974913476d5dd5144a36c0e2731592a8da02c34a,
build16 attempt2 success, user confirmed iPhone success.
Preserved tag:viewer-verified-20261118. Release build16 retained.
Existing IPA asset762896337:536111393 bytes;
SHA256 d4fd861943c82c8f3bdd8802f1a208ba17afda6999f8fb137071c37ae4a98c6e.

Optional cg_subtitles.json is stored with private viewer assets, not this source repository.
Matches855 original voice cues using op_index, full source location, and voice identity.
No audio transcription, generated dialogue or media review.
Text appears lower right during playback; stop, completion and content changes clear it.
Pause retains text. Original default player-name placeholder is rendered consistently.
Missing subtitle data hides the panel without blocking existing playback.

Native model extraction/loading, native build scripts and export preset are unchanged.
Viewer workflow now sparse-checks out project/vendor to avoid fetching newly added story assets.
An independent story-ios workflow reads story_project/vendor and publishes story-build tags.

Local checks:
-855/855 original voice cues matched,0 missing.
-Synthetic matching4/4, child/wrapper0/0, stderr empty.
-Godot4.4.1 subtitle/runtime9/9, child/wrapper0/0, stderr empty.
  Includes main-script parsing, playback, pause, stop, natural completion,
  missing caption and1320x800/844x390 panel bounds.
-Rendered synthetic sample screenshot inspected; no game dialogue displayed in test.
-Both workflows parsed using isolated PyYAML6.0.3.

Earlier unrecorded synthetic audio checks reported delayed playback cleanup at shutdown.
The fixture now waits for audio shutdown; final recorded run has no stderr.
This is not an iOS compilation, signing or on-device rendering receipt.
Do not modify an installed IPA to apply these source changes; rebuild and re-sign.
Existing signed app and old downloadable IPA remain unchanged.
