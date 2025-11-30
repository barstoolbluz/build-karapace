# Karapace - Nix/Flox Build Environment

Build modern Karapace versions using **Nix** and **Flox** - Apache Kafka® Schema Registry and REST Proxy implementation.

## Why This Exists

**Problem:** Need a modern, open-source alternative to Confluent Schema Registry for Kafka
- Karapace provides drop-in replacement for Schema Registry and Kafka REST Proxy
- Compatible with Schema Registry 6.1.1 API
- Supports Avro, JSON Schema, and Protobuf
- Leader/Replica architecture for high availability

**Solution:** This repository provides build tooling to package Karapace using:
- **[Flox Manifest Builds](https://flox.dev/docs/concepts/manifest-builds/)** - Declarative TOML-based builds
- **Nix Expressions** - For reproducible builds and Nix ecosystem integration

## Supported Versions

| Version | Released | Python | Features | Use Case |
|---------|----------|--------|----------|----------|
| **5.0.3** | Nov 2024 | 3.10-3.12 | Schema Registry + REST Proxy | Production ⭐ |

## Quick Start

### Option 1: Flox Manifest Builds (Recommended)

```bash
# Clone this repository
git clone <your-repo-url>
cd build-karapace

# Activate the build environment
flox activate

# Build Karapace 5.0.3
flox build karapace

# Use the built package
./result-karapace/bin/karapace --version
source result-karapace/bin/activate
karapace --help
```

**Available builds:**
- `karapace` - Full Karapace installation (Schema Registry + REST Proxy) version 5.0.3

### Option 2: Nix Expression (Planned)

Traditional `nix-build` support planned for broader Nix community compatibility.

## How It Works

All build methods:

1. **Use vendored source tarballs** from `vendor/` directory
2. **Create a Python virtualenv** in the output directory
3. **Install build dependencies** (setuptools, setuptools-scm, setuptools-golang)
4. **Build Go extensions** for Protobuf support from vendored Aiven Avro fork
5. **Install Karapace dependencies** from PyPI (cached in FOD)
6. **Package as Nix store path** with proper runtime wrappers

This approach:
- ✅ Uses vendored source tarballs for reproducibility
- ✅ Includes Protobuf/Go extension support
- ✅ Provides Schema Registry and REST Proxy
- ✅ Supports Avro, JSON Schema, Protobuf
- ✅ Self-contained - builds without external GitHub dependencies
- ✅ Enables version tracking and updates via branching strategy

## Use Cases

### Development Environments

```bash
flox activate
flox build karapace
source result-karapace/bin/activate

# Start Schema Registry
karapace karapace.config.json

# Start REST Proxy
karapace_rest_proxy rest-proxy.config.json
```

### Production Deployments

Compose with Flox environments for Kafka/Zookeeper:

```toml
[include]
environments = [
  { remote = "team/kafka-cluster" },
]

[hook]
on-activate = '''
  source /path/to/result-karapace/bin/activate
  export KARAPACE_BOOTSTRAP_URI="kafka:9092"
'''

[services]
karapace-registry.command = "karapace karapace.config.json"
karapace-rest.command = "karapace_rest_proxy rest-proxy.config.json"
```

## Vendored Sources & Version Management

This repository uses a **vendored source** strategy to ensure reproducible builds even if upstream sources disappear.

### Vendored Tarballs

All required source tarballs are stored in `vendor/`:
- `karapace-5.0.3.tar.gz` - Main Karapace source from GitHub release
- `avro-5a82d57f2a650fd87c819a30e433f1abb2c76ca2.tar.gz` - Aiven's patched Avro library

Python dependencies from PyPI are cached in a Fixed-Output Derivation (FOD) but not vendored, as PyPI provides stable, long-term package availability.

### Version Management Strategy

**`main` branch** = Latest stable version
- Contains current version's Nix expression and vendored sources
- Always builds the most recent stable release

**Version-specific branches** = Frozen historical versions
- When a new version is released, current `main` is branched to `karapace-X.Y.Z`
- Each branch preserves its own `vendor/` directory
- Allows building any historical version forever, even if upstream sources are deleted

Example workflow for releasing 5.0.4:
1. Branch current `main` to `karapace-5.0.3`
2. On `main`: Add new tarballs to `vendor/`, update version in `karapace.nix` to `5.0.4`
3. Users can build 5.0.4 from `main` or 5.0.3 from the `karapace-5.0.3` branch

## Configuration

Karapace requires configuration files. Example minimal config:

**karapace.config.json:**
```json
{
  "bootstrap_uri": "kafka:9092",
  "registry_host": "0.0.0.0",
  "registry_port": 8081,
  "topic_name": "_schemas"
}
```

**rest-proxy.config.json:**
```json
{
  "bootstrap_uri": "kafka:9092",
  "rest_host": "0.0.0.0",
  "rest_port": 8082
}
```

Environment variables can override config with `KARAPACE_` prefix:
- `KARAPACE_BOOTSTRAP_URI` overrides `bootstrap_uri`
- `KARAPACE_REGISTRY_PORT` overrides `registry_port`

## About Karapace

[Karapace](https://karapace.io) is an open-source implementation of Apache Kafka REST and Schema Registry.

### Key Features

- **Schema Registry**: Central repository for schemas (Avro, JSON Schema, Protobuf)
- **Kafka REST Proxy**: RESTful interface for Kafka operations
- **Compatibility**: Drop-in replacement for Confluent Schema Registry 6.1.1
- **HA Support**: Leader/Replica architecture
- **Observability**: Metrics and OpenTelemetry support
- **Authentication**: OAuth2 support

### Links

- **Official Repository**: https://github.com/Aiven-Open/karapace
- **Official Website**: https://karapace.io
- **PyPI Package**: https://pypi.org/project/karapace/
- **Docker Images**: ghcr.io/aiven-open/karapace

## License

Karapace is licensed under the Apache License 2.0.

This build environment configuration is provided as-is for building Karapace.

## Acknowledgments

- **Aiven** for creating and maintaining Karapace
- **Flox** for declarative environment and build system
- **Nix Community** for reproducible build infrastructure
