# Security policy

## Supported versions

Vacuum is currently a pre-release, read-only scanner. Security fixes are provided
for the latest published version only.

## Reporting a vulnerability

Please do not open a public issue for a vulnerability. Use GitHub's private
vulnerability reporting under **Security → Advisories → Report a vulnerability**
in `merttcetn/vacuum-mac`.

Include:

- the Vacuum and macOS versions;
- the affected rule or filesystem path shape, with secrets removed;
- reproduction steps;
- whether a process guard, symlink, path containment, identity revalidation,
  restore, or purge boundary is involved; and
- the impact you believe is possible.

Do not include credentials, private session data, or a user's real home-directory
contents. A minimal temporary-directory fixture is preferred.

We will acknowledge a complete report within seven days and coordinate disclosure
after a fix is available. Please allow a reasonable remediation window before
publishing details.

## Security boundaries

The following are security-sensitive invariants:

- scanner rules are compiled into the application;
- protected data cannot enter a cleanup plan;
- symlinks are never followed;
- ownership, approved-root containment, device/inode identity, and process guards
  are rechecked immediately before mutation;
- only records created by Vacuum can be restored or purged;
- restore never overwrites an existing item; and
- the app runs without a privileged helper or telemetry.

Any behavior that violates one of these boundaries should be reported privately,
even if the read-only beta prevents immediate deletion.
