# Hardcharger Power BI connector

See README.md and docs/architecture.md. Use the documented Adbc.Connection and
SqlView.Generator pattern with the native Hardcharger ADBC DLL over Chargewire.
Names from before the protocol rename (servers released before it) live only in
PreRenameCompat.pqm and its tests.
Keep credentials in Extension.CurrentCredential, never in shared query arguments
or folding identifiers. Update CHANGELOG.md for user-visible changes. Pin and
checksum dependencies in dependencies.json. Run the full Windows CI suite before
a release; only tag releases after version/changelog match. Never change the
permanent Hardcharger MSI UpgradeCode/component GUIDs or reuse GizmoSQL GUIDs.
