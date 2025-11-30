{ stdenv
, lib
, python311
, curl
, cacert
, go_1_23
, rustc
, cargo
, unzip
, zip
, patchelf
, makeWrapper
, gnutar
, gzip
, coreutils
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

  # Vendored source tarballs (relative to this .nix file in .flox/pkgs/)
  vendorDir = ../../vendor;

  # Extract Karapace source from vendored tarball
  # Using a minimal FOD to avoid store references that mkDerivation can introduce
  karapaceSrc = builtins.derivation {
    name = "karapace-${version}-source";
    system = stdenv.system;
    builder = "${stdenv.shell}";
    PATH = "${lib.makeBinPath [ coreutils gnutar gzip ]}";
    args = [
      "-c"
      ''
        mkdir -p $out
        cd $out
        tar xzf ${vendorDir}/karapace-${version}.tar.gz --strip-components=1
      ''
    ];

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    outputHash = "sha256-Nj+pcV5/5gTUtg5RzfCXzXiIizWb56laAOZWviovL0w=";
  };

  # Fixed-output derivation to download pip packages (allowed network access)
  pipCache = stdenv.mkDerivation {
    name = "karapace-${version}-pip-cache";

    nativeBuildInputs = [ pythonPkg curl cacert go_1_23 rustc cargo unzip zip patchelf ];

    src = karapaceSrc;

    buildPhase = ''
      mkdir -p $out

      # Set version for setuptools-scm
      export SETUPTOOLS_SCM_PRETEND_VERSION_FOR_KARAPACE="${version}"

      # Create temporary venv for downloading
      ${pythonPkg}/bin/python -m venv venv
      source venv/bin/activate

      pip install --upgrade pip setuptools wheel

      # Download build dependencies (including Cython for aiokafka)
      pip download pip setuptools wheel setuptools_scm setuptools-golang build Cython --dest $out

      # Extract the patched avro dependency from vendored tarball (lang/py subdirectory)
      mkdir -p /tmp/avro-extract
      tar xzf ${vendorDir}/avro-5a82d57f2a650fd87c819a30e433f1abb2c76ca2.tar.gz -C /tmp/avro-extract
      cd /tmp/avro-extract/avro-5a82d57f2a650fd87c819a30e433f1abb2c76ca2/lang/py
      python setup.py sdist --dist-dir $out
      cd -

      # Download all Karapace dependencies from pyproject.toml
      # This downloads wheels and source distributions for all dependencies
      pip download . --dest $out

      # Pre-build the protopace Go extension as a wheel
      echo "Pre-building protopace Go extension..."
      cd go/protopace

      # Set up Go environment
      export GOPATH=/tmp/gopath
      export GOCACHE=/tmp/go-build
      mkdir -p /tmp/gopath /tmp/go-build

      # Download and vendor dependencies
      go mod download
      go mod vendor

      cd ../..

      # Build the karapace wheel with the Go extension
      # This runs during FOD where network is available for Go dependencies
      python -m venv /tmp/build-venv
      source /tmp/build-venv/bin/activate
      pip install --upgrade pip setuptools wheel setuptools-scm setuptools-golang build

      # Set version for setuptools-scm
      export SETUPTOOLS_SCM_PRETEND_VERSION_FOR_KARAPACE="${version}"

      # Build wheel (this will compile the Go extension)
      python -m build --wheel --outdir $out

      # Fix the wheel to strip store references from compiled .so files
      cd $out
      WHEEL_FILE=$(ls karapace-*.whl)
      mkdir -p /tmp/wheel-fix
      cd /tmp/wheel-fix
      unzip -q $out/$WHEEL_FILE

      # Strip references from the Go extension library to make FOD pure
      find . -name "*.so" -exec patchelf --shrink-rpath {} \; || true
      find . -name "*.so" -exec patchelf --remove-rpath {} \; || true

      # Repack the wheel (zip all contents, not just karapace-* pattern)
      rm $out/$WHEEL_FILE
      zip -qr $out/$WHEEL_FILE .
      cd $out
      rm -rf /tmp/wheel-fix

      deactivate
    '';

    installPhase = "true";

    outputHashMode = "recursive";
    outputHashAlgo = "sha256";
    # Platform-specific hashes (pip downloads different wheels per platform)
    # NOTE: Hashes include Cython (required for building aiokafka from source)
    outputHash =
      if stdenv.system == "x86_64-linux" then
        "sha256-H2EkVdkT1EBwS7JPU8i88YvrPM/wAsNOCGWGI0WlUvE="  # May need update - built before Cython was added
      else if stdenv.system == "aarch64-darwin" then
        "sha256-A5G45CyDa6T/vFs7pNzuAeAQO0jvA78U15Dgkbvy4P4="
      else if stdenv.system == "x86_64-darwin" then
        lib.fakeHash  # TODO: Update with actual hash when building on this platform
      else if stdenv.system == "aarch64-linux" then
        lib.fakeHash  # TODO: Update with actual hash when building on this platform
      else
        throw "Unsupported system: ${stdenv.system}";
  };

in
stdenv.mkDerivation {
  pname = "karapace";
  inherit version;

  src = karapaceSrc;

  nativeBuildInputs = [
    pythonPkg
    go_1_23       # Required for protopace Go extension
    rustc         # Required for some dependencies
    cargo         # Required for some dependencies
    makeWrapper   # Required to create wrapper scripts with LD_LIBRARY_PATH
  ];

  buildInputs = [
    pythonPkg
    stdenv.cc.cc.lib  # Required for libstdc++.so.6 needed by ujson and other compiled packages
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

    # Create virtualenv in $out
    ${pythonPkg}/bin/python -m venv $out
    source $out/bin/activate

    # Install from pre-downloaded packages (no network needed)
    echo ""
    echo "Installing Karapace from cached packages..."
    pip install --no-index --find-links ${pipCache} \
      --upgrade pip setuptools wheel

    # Install avro first from our patched version
    echo ""
    echo "Installing avro from patched source..."
    pip install --no-index --find-links ${pipCache} avro

    # Install all karapace dependencies from cache (without karapace itself yet)
    echo ""
    echo "Installing dependencies..."
    pip install --no-index --find-links ${pipCache} \
      accept-types aiohttp aiokafka async_lru cachetools confluent-kafka \
      cryptography fastapi isodate jsonschema lz4 networkx protobuf \
      pydantic pydantic-settings pyjwt python-dateutil python-snappy \
      rich tenacity typing-extensions ujson watchfiles xxhash zstandard \
      prometheus-client yarl opentelemetry-api opentelemetry-sdk \
      opentelemetry-exporter-otlp dependency-injector \
      uvicorn httpx jinja2 python-multipart email-validator

    # Finally install karapace wheel with --no-deps since all deps are already installed
    echo ""
    echo "Installing Karapace wheel (without dependencies)..."
    pip install --no-index --find-links ${pipCache} --no-deps karapace

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

  postFixup = ''
    # The entry points generated by pip are broken in Karapace 5.0.3
    # karapace.__main__ doesn't have a main() function - it runs directly
    # We need to create custom wrappers that run the modules correctly

    # Remove broken pip-installed entry points
    rm -f $out/bin/karapace $out/bin/karapace_rest_proxy

    # Create working karapace wrapper (runs both registry and REST proxy based on config)
    makeWrapper $out/bin/python $out/bin/karapace \
      --add-flags "-m karapace" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}"

    # Create karapace_rest_proxy wrapper (for convenience, same as karapace)
    makeWrapper $out/bin/python $out/bin/karapace_rest_proxy \
      --add-flags "-m karapace.kafka_rest_apis" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}"

    # Wrap the other entry points that work correctly
    for prog in $out/bin/karapace_mkpasswd $out/bin/karapace_schema_backup; do
      if [ -f "$prog" ]; then
        wrapProgram $prog \
          --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [ stdenv.cc.cc.lib ]}"
      fi
    done
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
