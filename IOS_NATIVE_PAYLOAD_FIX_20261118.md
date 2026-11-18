# build-15 opens but native models do not load

User confirmed on iPhone: UI, portraits and audio work; native models do not.
This is separate from the build-14 root-node startup timing defect.

## Actual package evidence

build-15 IPA SHA256:
229453bf36c5a00d2e39d21323384f6df60780f4a4ae8e59690db43a54ebd56e

Read-only inspection found 2060 PCK entries and valid directory JSON, but zero
raw .moc3 and .atlas entries. Only one raw PNG (the application icon) remains;
149 imported textures exist. The source asset repository contains the native
inputs. Checking their existence before export did not check the final package.

Cubism reads model JSON and MOC bytes directly using FileAccess. Spine also
reads original atlas/skeleton inputs. The old mobile directory mirror cannot
recover a missing source PNG from an imported texture merely by copying files.
These are proven package/loader mismatches, not proof of a device GPU defect.

Both frameworks are embedded arm64 device Mach-O binaries and are linked by
the application. Static inspection does not establish runtime class registration.
Cubism LC_BUILD_VERSION declares 18.5, while the application declares 13.0;
the user's exact iOS minor version is unknown. This remains a separate
compatibility concern, not a claimed cause of the missing input files.

## Repair

- Build a checked native_payload.zip from original native inputs, including
  source textures, without interpreting audio or media contents.
- Require all catalog/model file references to exist before creating it.
- Explicitly include payload and JSON in the Godot export.
- Verify every archived file's size/hash from the actual exported PCK in CI.
- Extract into a content-addressed user cache; write the completion marker last.
  A partial cache is repaired rather than being trusted because its folder exists.
- Mobile native readers use these intact files. Existing imported portrait and
  audio loading remains in place.
- Display native extraction/class-registration/loading failures in the viewer.

## Local validation

Evidence root: story_integration/story_integration/evidence/rea_connection_20261117.

| Receipt | PID | Child/wrapper | Result |
| --- | --- | --- | --- |
| ipa15_payload_build02 | 36840 | 0/0 | 297 files, 152 required paths, 0 missing |
| ipa15_payload_import01 | 18392 | 0/0 | fixture imported |
| ipa15_payload_export01 | 42708 | 0/0 | actual fixture PCK exported |
| ipa15_payload_pack_verify01 | 36560 | 0/0 | all 297 files verified from PCK |
| ipa15_native_payload_runtime01 | 36608 | 0/0 | 7/7 |
| ipa15_native_payload_runtime02 | 43388 | 0/0 | final cache helper 7/7 |
| ipa15_native_cache_load01 | 31248 | 0/0 | 12/12 Windows native reader checks |

All listed stderr files are empty. Runtime checks cover extraction, missing-file
cache repair and repeat launch without loading media. Native checks cover three
Live2D models' canvas/parameters/motions and ordinary main-menu Spine data;
they do not load CG or audio and are not iOS rendering verification.

Initial payload generation exited 1 after writing its files because a diagnostic
print called stat.st_size as a function. Corrected to the property, retained the
first output and built a new output directory for successful build02.

No new IPA or iPhone success is asserted by these Windows tests. After building,
verify on-device extension registration, rendering, animation and cache creation.
The larger payload preserves raw files in addition to imported textures, so
package size will increase.
