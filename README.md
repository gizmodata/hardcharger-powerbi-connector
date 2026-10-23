<p align="center">
  <a href="https://github.com/gizmodata/hardcharger">
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="docs/assets/hardcharger-banner-dark.png">
      <img src="docs/assets/hardcharger-banner-light.png" alt="Hardcharger™" width="400">
    </picture>
  </a>
</p>

# Hardcharger Power BI Connector

Connect Power BI Desktop to **Hardcharger™** using the native [Hardcharger ADBC driver](https://github.com/gizmodata/hardcharger-adbc) and [Warp SQL](https://github.com/gizmodata/warp-sql). Arrow columnar results, Import, DirectQuery, DuckDB query folding and catalog/schema/table navigation.

[![CI](https://github.com/gizmodata/hardcharger-powerbi-connector/actions/workflows/ci.yml/badge.svg)](https://github.com/gizmodata/hardcharger-powerbi-connector/actions/workflows/ci.yml)

## Install

1. Download **Hardcharger-PowerBI-Setup-x64.msi** from the [latest release](https://github.com/gizmodata/hardcharger-powerbi-connector/releases/latest).
2. Run the signed installer, then restart Power BI Desktop.
3. Choose **Get Data → Database → Hardcharger**.

The MSI installs `libadbc_driver_hardcharger.dll` and its licenses under `Program Files\Hardcharger Power BI Connector`, adds that directory to the system PATH, and installs the signed `Hardcharger.pqx` into both Power BI Custom Connectors directories under the installing user's Documents. It appends the signing certificate to Power BI's trusted connector policy so the default Recommended security level can load the connector. Install interactively as the intended Power BI user with administrator elevation; SYSTEM deployments and other Windows users need the connector copied to their own Documents directories. GizmoSQL can remain installed alongside it.

Requires Windows x64, Hardcharger 2.0.0+ and a current Power BI Desktop with `Adbc.Connection` and `SqlView.Generator`. CI uses Power Query SDK Tools **2.160.2**. Power BI Desktop supplies the M engine separately; the installer does not update Desktop. This is a signed custom connector, not a Microsoft-certified built-in connector.

## Connect

Enter the hostname, port (normally **31337**) and TLS choice. TLS should be enabled for production; disable it for a local plain HTTP development server. Optional settings allow certificate-verification bypass for development and a default catalog. Use a hostname rather than a URI; raw driver option names and credentials do not belong in query parameters.

Choose **Username/Password**, **Bearer token**, or **OAuth (Browser)**. The bearer token must be a Warp SQL access token issued by Hardcharger, rather than an identity provider's raw ID token. Browser sign-in uses Hardcharger's Warp SQL OAuth flow on the same HTTP(S) port; configure the identity provider on the server. Its certificate must be trusted by Windows because Power Query's HTTP client cannot bypass TLS verification. Browser tokens cannot be refreshed noninteractively; use username/password for unattended gateway refresh. Gateway administrators must install the driver and connector on the gateway machine and enable custom connectors.

```powerquery
// TLS enabled
Source = Hardcharger.Contents("db.example.com", 31337, true)
// Plain HTTP development server
Source = Hardcharger.Contents("localhost", 31337, false)
```

Create model relationships using Power BI's **Manage relationships → Autodetect**, or manually. The connector emits primary key metadata. PQTest cannot verify relationships in the Desktop model.

## Architecture and current Microsoft guidance

```text
Power BI Desktop / Power Query
  Hardcharger.pqx
    Adbc.Connection + SqlView.Generator
      libadbc_driver_hardcharger.dll (AdbcDriverHardchargerInit)
        Warp SQL / HTTP(S) / Arrow IPC
          Hardcharger
```

This follows Microsoft's current [ADBC connector fundamentals](https://learn.microsoft.com/en-us/power-query/adbc), [advanced patterns](https://learn.microsoft.com/en-us/power-query/adbc-advanced-patterns) and [SQL generator architecture](https://learn.microsoft.com/en-us/power-query/adbc-sql-generator). The driver configuration and type metadata follow the [Microsoft DuckDB ADBC sample](https://github.com/microsoft/DataConnectors/tree/master/samples/DuckDbFlightSQL); Hardcharger needs its own driver, entrypoint, URI and auth options. FlightSQL and ODBC are not used. The explicit shared source identity lets tables from the same target fold cross-table joins.

See [the architecture review](docs/architecture.md) for the comparison, upstream revisions and validation limits.

## Develop and test

On Windows with PowerShell 7, .NET 10, Python 3.14 and GitHub CLI:

```powershell
./scripts/Install-Dependencies.ps1 Sdk
# Locally set PQTEST and MAKEPQX to the executable paths printed above.
./scripts/Build-Connector.ps1
./scripts/Install-Dependencies.ps1 Driver
./scripts/Install-Dependencies.ps1 Server
# Set HARDCHARGER_SERVER to the extracted hardcharger-server.exe.
python -m pip install adbc-driver-manager==1.12.0 pyarrow==23.0.1
./scripts/Test-Connector.ps1
```

CI runs the full inherited nine-query GizmoSQL suite and additional correctness/regression queries against a real released Hardcharger server and native ADBC DLL. It fails on missing/zero results and any failed query, and saves JSON and server logs as artifacts. Native-driver tests cover catalog discovery, the inherited DuckDB SQL dialect script, bearer auth, rejected credentials and TLS downgrade prevention. The retained `tests/legacy-odbc-sqltables.c` is an archived ODBC-era diagnostic, superseded by the ADBC catalog tests.

For a development build, copy `Hardcharger.mez` to `[Documents]\Power BI Desktop\Custom Connectors` and allow unsigned connectors in Desktop's security options. The native driver must be on PATH. For signed manual installation, copy `Hardcharger.pqx` and have an administrator configure the [trusted certificate policy](https://learn.microsoft.com/en-us/power-bi/connect-data/desktop-trusted-third-party-connectors); the MSI performs these steps.

Set `EnableTraceOutput = true` in `Hardcharger.pq` for local diagnostics. Leave it disabled in release builds. Desktop Import/DirectQuery visuals, credential dialogs, interactive IdP sign-in and model relationships also need Desktop acceptance testing; headless PQTest validates M evaluation and folding queries, not the full Desktop UI.

## Release and signing

Update the connector version and changelog, push main, then tag `vX.Y.Z`. CI tests the tagged source before signing, verifies the PQX OPC signature and MSI Authenticode signature, exercises installation/repair/uninstallation, and publishes `.pqx`, `.mez`, `.msi`, checksums and build provenance. All download versions/digests are recorded in [dependencies.json](dependencies.json).

The `production` GitHub environment contains `AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_KEY_VAULT_URI` and `AZURE_CERT_NAME`. Its Azure federated credential must match this repository's actual OIDC subject (new repositories use immutable owner/repository IDs). The EV private key stays in Azure Key Vault. See [signing setup](docs/signing.md).

## License and attribution

Apache-2.0. Derived from [GizmoSQL Power BI Connector](https://github.com/gizmodata/gizmosql-powerbi-connector), preserving its Git history and nine regression queries. SQL generator: Curt Hagenlocher's quack-net (Apache-2.0), with text predicate contributions from spiceai/powerbi-connector (MIT). Native driver licenses and third-party notices ship in the MSI.

<p align="center"><a href="https://gizmodata.com"><img src="docs/assets/gizmodata-logo.png" alt="GizmoData™" width="56"></a><br><sub>Built by GizmoData™. Hardcharger™ and GizmoData™ are trademarks of GizmoData LLC.</sub></p>
