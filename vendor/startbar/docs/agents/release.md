# Releasing StartBar

Read this before merging to `main`, tagging, or publishing a release.

## What ships when

- **Merging to `main` is the release.** `omarchy plugin update` fast-forwards a user's install to the default branch's HEAD. It does not look at tags or GitHub releases, so every commit on `main` reaches users on their next update.
- **The marketplace verifies one exact commit.** The listing for `io.github.bmaltais.startbar` records the commit a maintainer approved. Any later commit on `main` shows as "Update unverified" until that commit is verified too (step 6).
- **Tags and GitHub releases are the changelog.** Nothing installs from them.

## Branches

Work accumulates on `release/<version>` (for example `release/1.2.0`). Branch from it and target pull requests at it. `main` only moves when a release branch is merged into it.

A branch that needs a PR that is still open can be based on it and opened against it; say so in the PR body. When that PR is squash-merged its commits are rewritten, so rebase the dependent branch with `git rebase --onto origin/release/<version> <old base>` and retarget the PR at `release/<version>`.

The open release branch is the highest `release/<version>` on origin whose `v<version>` tag does not exist; `scripts/open-release.sh` prints it. When every release branch is tagged, it says so: start the next one from `main` (step 7) before opening the PR.

Name the branch `release/<version>`, never `v<version>`: a branch and a tag with the same name make `git push origin v1.2.0` ambiguous.

## Steps

1. On the release branch, set the same version in `manifest.json` and `package.json` (a test fails if they differ).
2. Run `npm run check`, then `scripts/smoke.sh`, and look at the screenshots. Walk the parts of the manual checklist in `CONTRIBUTING.md` that the changes touch, with a real mouse.
3. Check the tag is free: `git ls-remote --tags origin`.
4. Open a pull request from the release branch into `main`; the maintainer merges it (the agent's `gh pr merge` is blocked as a merge without review, here and for PRs into a release branch). Users start receiving it now. In the PR body, list under "Checked" only what you ran; put anything that needs a real mouse under "Needs a human check".
5. Tag the merge commit `v<version>`, push the tag, and publish a GitHub release with `gh release create v<version> --latest`. Say in the notes what changed for users, and call out anything they must do by hand.
6. File the marketplace's "Verify or update a listed plugin" issue on `omacom/omarchy-plugin-marketplace` (template `verify-plugin.yml`): action "Verify and publish a newer upstream commit", the plugin id, `https://github.com/bmaltais/StartBar`, and the full 40-character SHA of `main`. The issue is public and filed in the owner's name, so show them the text first.
7. Start the next `release/<version>` branch from `main`.

## Version numbers

Bump the minor version for features and for fixes shipped with them, the patch version for a fix-only release. A change that makes users edit their config or changes the plugin id is breaking: say so at the top of the release notes with the exact steps.

The plugin id is permanent on the marketplace. A retired id cannot be reused, and changing it orphans every existing install.
