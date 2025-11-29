{ stdenv
, lib
, python311
, curl
, cacert
, go_1_23
, rustc
, cargo
}:

let
  # ===========================================================================
  # USER CONFIGURATION
  # ===========================================================================
  version = "5.0.3";           # Karapace version to build
  pythonVersion = "3.11";      # Python version (3.10, 3.11, or 3.12 supported)

  # Version metadata for reference
  versionInfo = {
    "5.0.3" = {
      pythonVersions = "3.10, 3.11, 3.12";
      releaseDate = "2024-11-18";
      description = "Latest stable release";
    };
  };

  # ===========================================================================
  # Build Configuration
  # ===========================================================================

  # Use python311 from manifest
  pythonPkg = python311;

  # Get version metadata
  meta = versionInfo.${version} or {
    pythonVersions = "Unknown";
    releaseDate = "Unknown";
    description = "Unknown version";
  };

  # Fetch Karapace source from GitHub
  karapaceSrc = stdenv.mkDerivation {
    name = "karapace-${version}-source";

    nativeBuildInputs = [ curl cacert ];

    src = builtins.toFile "download" "";

    unpackPhase = ":";

    buildPhase = ''
      mkdir -p $out
      cd $out
      curl -L "https://github.com/Aiven-Open/karapace/archive/refs/tags/${version}.tar.gz" -o source.tar.gz
      tar xzf source.tar.gz --strip-components=1
      rm source.tar.gz
    '';

    installPhase = "true";

    dontPatchShebangs = true;
    dontStrip = true;
    dontPatchELF = true;

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-Nj+pcV5/5gTUtg5RzfCXzXiIizWb56laAOZWviovL0w=";
  };

  # Fixed-output derivation to download pip packages (allowed network access)
  pipCache = stdenv.mkDerivation {
    name = "karapace-${version}-pip-cache";

    nativeBuildInputs = [ pythonPkg curl cacert go_1_23 rustc cargo ];

    src = karapaceSrc;

    buildPhase = ''
      mkdir -p $out

      # Set version for setuptools-scm
      export SETUPTOOLS_SCM_PRETEND_VERSION_FOR_KARAPACE="${version}"

      # Create temporary venv for downloading
      ${pythonPkg}/bin/python -m venv venv
      source venv/bin/activate

      pip install --upgrade pip setuptools wheel

      # Download build dependencies
      pip download pip setuptools wheel setuptools_scm setuptools-golang --dest $out

      # Download and extract the patched avro dependency (lang/py subdirectory)
      mkdir -p /tmp/avro-extract
      curl -L "https://github.com/aiven/avro/archive/5a82d57f2a650fd87c819a30e433f1abb2c76ca2.tar.gz" | \
        tar xz -C /tmp/avro-extract
      cd /tmp/avro-extract/avro-5a82d57f2a650fd87c819a30e433f1abb2c76ca2/lang/py
      python setup.py sdist --dist-dir $out
      cd -

      # Download all Karapace dependencies from pyproject.toml
      # This downloads wheels and source distributions for all dependencies
      pip download . --dest $out
    '';

    installPhase = "true";

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    # Platform-specific hashes (pip downloads different wheels per platform)
    outputHash = "sha256-eGtJKihSALtu8J/GBnsQZkbapwTPCk2yacmWP8PPuB0=";
  };

in
stdenv.mkDerivation {
  pname = "karapace";
  inherit version;

  src = karapaceSrc;

  nativeBuildInputs = [
    pythonPkg
    go_1_23      # Required for protopace Go extension
    rustc        # Required for some dependencies
    cargo        # Required for some dependencies
  ];

  buildInputs = [
    pythonPkg
  ];

  buildPhase = ''
    echo "========================================="
    echo "Building Karapace from source"
    echo "Version: ${version}"
    echo "Python: ${pythonVersion}"
    echo "Release: ${meta.releaseDate}"
    echo "========================================="

    # Set version for setuptools-scm
    export SETUPTOOLS_SCM_PRETEND_VERSION_FOR_KARAPACE="${version}"

    # Disable Go proxy to prevent network access during build
    export GOPROXY=off

    # Create virtualenv in $out
    ${pythonPkg}/bin/python -m venv $out
    source $out/bin/activate

    # Install from pre-downloaded packages (no network needed)
    echo ""
    echo "Installing Karapace from cached packages..."
    pip install --no-index --find-links ${pipCache} \
      --upgrade pip setuptools wheel setuptools-scm setuptools-golang

    # Install Karapace from source directory using cached dependencies
    echo ""
    echo "Installing Karapace..."
    # First install avro from the sdist we created
    pip install --no-index --find-links ${pipCache} avro
    # Now install Karapace using the cached wheels
    # We use PIP_NO_INDEX and provide find-links to use only our cache
    pip install --no-index --find-links ${pipCache} --no-deps .
    # Then install remaining dependencies
    pip install --no-index --find-links ${pipCache} \
      accept-types aiohttp aiokafka async_lru cachetools confluent-kafka \
      cryptography dependency-injector fastapi pydantic isodate jsonschema \
      lz4 networkx opentelemetry-api opentelemetry-exporter-otlp opentelemetry-sdk \
      protobuf prometheus-client pydantic-settings pyjwt python-dateutil \
      python-snappy rich tenacity typing-extensions ujson watchfiles xxhash \
      zstandard yarl

    # Verify installation
    echo ""
    echo "========================================="
    echo "✅ Installation complete!"
    echo "========================================="
    echo "Karapace ${version} installed successfully"
    echo ""
    echo "Installed executables:"
    ls -1 $out/bin/ | grep -E '^karapace' || true
  '';

  installPhase = ''
    echo "Virtualenv created in $out"
  '';

  dontStrip = true;
  dontPatchELF = true;
  dontPatchShebangs = false;

  meta = with lib; {
    description = "Karapace - Apache Kafka Schema Registry & REST Proxy";
    longDescription = ''
      Karapace ${version} - Open-source implementation of Apache Kafka
      Schema Registry and REST Proxy.

      Features:
      - Schema Registry (Avro, JSON Schema, Protobuf)
      - Kafka REST Proxy
      - Compatible with Schema Registry 6.1.1 API
      - Leader/Replica HA architecture
      - OAuth2 authentication support

      Release Date: ${meta.releaseDate}
      Python Versions: ${meta.pythonVersions}

      To change version: Edit version in .flox/pkgs/karapace-5-0-3.nix
    '';
    homepage = "https://karapace.io";
    license = licenses.asl20;
    platforms = platforms.unix;
    mainProgram = "karapace";
  };
}
