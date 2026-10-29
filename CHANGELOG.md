# Changelog

## [Unreleased]

## [v1.1.0] - 2026-10-29

### Changed
- The connector now uses the Chargewire protocol: browser sign-in finds the server's Chargewire endpoint and still works with Hardcharger servers released before the rename. The Get Data port description and documentation name Chargewire. Connection settings and saved credentials are unchanged.
- Bundle the Hardcharger ADBC driver 2.1.0 and pass it the `adbc.chargewire.*` option keys. The driver still connects to Hardcharger servers released before the rename.
- CI runs the full test suite against Hardcharger 2.3.0.

## [v1.0.1] - 2026-10-23

### Added
- Hardcharger Power BI connector with Import, DirectQuery, hierarchical catalog/schema/table navigation and DuckDB query folding.
- Native Hardcharger ADBC 2.0.2 transport over Chargewire HTTP(S), username/password, bearer tokens and Power Query browser sign-in.
- Hardcharger branding throughout Get Data, documentation and the Windows MSI, using official Hardcharger artwork.
- Azure Key Vault signing and verification for the connector and MSI, with GitHub OIDC and non-exportable signing keys.
- All nine inherited Power Query regression queries, plus value assertions, joins, extended types, views, quoted identifiers and catalog isolation; native ADBC authentication, TLS and SQL dialect tests; installer install/repair/removal checks.

### Changed
- Follow Microsoft's documented `Adbc.Connection` / `SqlView.Generator` ADBC architecture and explicit driver metadata/type information.
- Pin Power Query SDK Tools 2.160.2, WiX 5.0.2 (the last release before OSMF terms), AzureSignTool 7.0.1, .NET 10 and current stable Azure signing SDKs. Verify downloaded SDK, server and native-driver SHA256 digests.
- Include TLS choice in the credential scope and reject invalid hosts/ports. Query folding identity excludes credentials and distinguishes TLS trust settings and catalogs.
- Give the MSI permanent Hardcharger-specific upgrade/component identities, preserving side-by-side GizmoSQL installations. Append connector trust without replacing unrelated certificate entries. Install the native driver in the Power Query host’s ADBC Drivers directory; the current engine does not use PATH for discovery.
- Retain upstream SQL dialect smoke coverage; replace the historical ODBC SQLTables diagnostic with native ADBC catalog tests.

### Fixed
- Initialize the installer verification log directory in isolated signing jobs so signed releases complete the same installation checks as development builds.
