# ADBC architecture review — 2026-10-23

Microsoft's July 30, 2026 documentation now describes `Adbc.Connection` plus
`SqlView.Generator` as the reference implementation. The old GizmoSQL comments
calling it an undocumented experimental workaround were stale. Reverting to
`Adbc.DataSource` would discard the explicit source identity needed for join folding.

References:
- https://learn.microsoft.com/en-us/power-query/adbc
- https://learn.microsoft.com/en-us/power-query/adbc-advanced-patterns
- https://learn.microsoft.com/en-us/power-query/adbc-sql-generator
- Microsoft DataConnectors `c7b9d81d0d1a62b5f5486f63087c8587e2ca0160`, `samples/DuckDbFlightSQL`
- GizmoSQL connector `8365c7b831c8324d3233334bc57b73135a2cc465`
- Hardcharger ADBC `a6c1db8bb563e3f3a5dbc829090765da197b1c44`; released DLL 2.0.2

The Microsoft sample supplies the driver metadata pattern and TypeInfo.pqm. We
retain the tested GizmoSQL SQL92 base and DuckDB override implementation, including
its text predicate folds, rather than replacing a dialect implementation solely
because a sample changed. All nine source queries remain. Credentials come only
from Extension.CurrentCredential; TLS is a required source parameter and part of
credential scope. Folding identity contains target/catalog/trust choices, never
credentials. Native options use the Hardcharger ADBC driver's own keys, not FlightSQL keys.

The official sample currently declares foreign-key helpers without applying them
to leaf tables. We preserve primary-key metadata, test it, and document Desktop's
relationship detection separately. Do not claim model relationship import from
headless M tests.

The checked-in dependency lock pins Power Query SDK Tools and signing packages
to the latest stable NuGet versions on the review date. MSI packaging uses WiX
5.0.2, the last pre-OSMF version; WiX 7 requires acceptance of new maintenance-fee
terms, which this project does not automatically accept. SDK versions and Desktop releases are separate: CI
validates SDK 2.160.2. Desktop UI and model acceptance testing is still separate.

Driver-discovery validation found that SDK 2.160.2 resolves unmanaged Folder/File
under the directory containing Microsoft.Mashup.Adbc.dll, in ADBC Drivers. It
rejects absolute paths and does not consult PATH or the ADBC manifest registry.
The MSI therefore installs to standalone Desktop's bin/ADBC Drivers/Hardcharger
by default, with INSTALLFOLDER override for other hosts. The SDK test setup uses
its own Mashup/ADBC Drivers/Hardcharger directory. Store Desktop's read-only app
package is not supported by this external native-driver installation.
