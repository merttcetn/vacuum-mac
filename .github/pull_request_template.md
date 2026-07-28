## What changed

Describe the user-visible behavior and why it is needed.

## Safety review

- [ ] No deletion root was broadened without fixture coverage.
- [ ] Symlinks remain un-followed and cleanup revalidates resource identity.
- [ ] Protected data cannot enter a cleanup plan.
- [ ] No shell or package-manager command is executed by the app.
- [ ] The read-only beta boundary is preserved, or enabling deletion is explicitly reviewed.

## Verification

- [ ] `xcodegen generate --spec project.yml`
- [ ] `xcodebuild ... test`
- [ ] Universal unsigned build verified with `scripts/verify-universal.sh`
