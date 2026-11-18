"""Derive the integrated build from the reviewed native build pipeline."""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
text = (root / ".github/workflows/story-ios.yml").read_text(encoding="utf-8")
text = text.replace("Build Standalone Story Player iOS IPA", "Build Viewer With Story iOS IPA")
text = text.replace("working-directory: ${{ runner.temp }}/story-player",
                    "working-directory: ../viewer-story")
text = text.replace('STORY_SOURCE_TAG: ${{ vars.STORY_SOURCE_TAG }}',
                    'STORY_SOURCE_TAG: story-source-20261118-01')
text = text.replace("sparse-checkout set vendor", "sparse-checkout set project vendor")
text = text.replace("sparse-checkout set story_project vendor",
                    "sparse-checkout set project story_project vendor")
anchor = '          python3 scripts/audit_story_player.py'
position = text.index(anchor)
end = text.index('\n      - name: 安装 Godot', position)
text = text[:position] + """          mkdir -p "$RUNNER_TEMP/viewer-input"
          cp -R "$GITHUB_WORKSPACE/." "$RUNNER_TEMP/viewer-input/"
          cp -R "$RUNNER_TEMP/assets/project/." "$RUNNER_TEMP/viewer-input/"
          python3 scripts/assemble_viewer_story.py \\
            --viewer "$RUNNER_TEMP/viewer-input" --story "$RUNNER_TEMP/story-player" \\
            --code "$GITHUB_WORKSPACE" --destination "$RUNNER_TEMP/viewer-story"
          test -f "$RUNNER_TEMP/viewer-story/data/scenario_full.json"
          du -sh "$RUNNER_TEMP/viewer-story"
""" + text[end:]
text = text.replace("验证独立播放器启动存读及原生模型", "验证查看器剧情入口播放存读及返回")
text = text.replace('PLAYER_TEST_RESULT="$RUNNER_TEMP/player-test-result.json"',
                    'VIEWER_STORY_TEST_RESULT="$RUNNER_TEMP/player-test-result.json"')
text = text.replace("res://scripts/test_player.gd", "res://scripts/test_viewer_story.gd")
text = text.replace("grep 'STORY_PLAYER_TEST'", "grep 'VIEWER_STORY_TEST'")
text = text.replace("VLoverStory.ipa", "VLoverViewer.ipa")
text = text.replace("V-Lover-Story-unsigned.ipa", "V-Lover-Viewer-Story-unsigned.ipa")
text = text.replace('TAG="story-build-', 'TAG="viewer-story-build-')
text = text.replace("$RUNNER_TEMP/viewer-story", "$GITHUB_WORKSPACE/../viewer-story")
(root / ".github/workflows/viewer-story-ios.yml").write_text(text, encoding="utf-8")
print("Generated .github/workflows/viewer-story-ios.yml")
