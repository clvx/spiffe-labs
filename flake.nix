{
  #https://dev.to/arnu515/easy-development-environments-with-nix-and-nix-flakes-21mb
  description = "SPIRE labs";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
  };

  outputs = { self, nixpkgs }: 
  let 
    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };

    spire-bundle = pkgs.fetchurl {
        url = "https://github.com/spiffe/spire/releases/download/v1.12.4/spire-1.12.4-linux-amd64-musl.tar.gz";
        #sha256 = pkgs.lib.fakeSha256;
        sha256 = "sha256-+x8Ex92CQi4djMVeLe3/Ze2j0fH7QKeHxbG2MJ1GQ28=";
      };

      # Optional: wrap it as a pkg so it's easier to use
      spire = pkgs.stdenv.mkDerivation {
        pname = "spire";
        version = "1.12.4";
        src = spire-bundle;
        nativeBuildInputs = [ pkgs.gnutar pkgs.gzip ]; # ensure we can extract tar.gz
        phases = [ "unpackPhase" "installPhase" ];
        unpackPhase = ''
          mkdir source
          tar -xzf $src -C source --strip-components=1
        '';
         installPhase = ''
          mkdir -p $out/bin
          # Install only binaries (adjust if needed)
          cp source/bin/spire-server $out/bin/
          cp source/bin/spire-agent $out/bin/
          chmod +x $out/bin/*

          ## Optionally include other non-executables for inspection/debugging
          mkdir -p $out/share/spire
          cp -r source/conf $out/share/spire/ || true
          #cp source/README.md $out/share/spire/ || true
        '';
                };
  in {

    #| Goal                           | Command       | Required flake output        |
    #| ------------------------------ | ------------- | ---------------------------- |
    #| Dev environment with `mkShell` | `nix develop` | `devShells.<system>.default` |
    #| Run/Expose package binary      | `nix shell`   | `packages.<system>.default`  |
    #| Run a binary from the flake    | `nix run`     | `packages.<system>.default`  |

    # to be used with `nix shell and nix run`
    packages.${system}.default = pkgs.buildEnv {
      name = "spire-env";
      paths = [ spire pkgs.jq pkgs.curl ];
    };

    # To be used with `nix develop`:
    # Copying the configuration files to the current directory.
    #  cp -r $(nix eval --raw .#spire)/share/spire/conf ./default-spire-conf
    # Manually obtain the configuration file:
    #  cat $(nix eval --raw .#spire)/share/spire/conf/server/server.conf
    devShells.${system}.default = pkgs.mkShell {
      packages = [
        spire
      ];


      
      shellHook = ''
        echo "Welcome to the SPIRE dev shell"

        if [ ! -f conf/server/server.conf ]; then
          echo "📦 Copying default SPIRE configs to ./conf/"
          mkdir -p conf/server conf/agent
          cp -r ${spire}/share/spire/conf/server/server.conf conf/server/
          cp -r ${spire}/share/spire/conf/agent/agent.conf conf/agent/
        fi

        export PATH=$PWD/bin:$PATH
        export SPIFFE_ID="spiffe://example.org/lab/service"
        echo "Run server: spire-server run -config conf/server/server.conf"
        spire-server run -config conf/server/server.conf &
        echo "Waiting for server to generate agent token..."
        for i in $(seq 1 60); do
          echo "Generate token:  spire-server token generate -spiffeID $SPIFFE_ID --output json | jq -r .value"
          SERVICE_TOKEN=$(spire-server token generate -spiffeID "$SPIFFE_ID" --output json 2>/dev/null | jq -r .value || true)
          if [ -n "$SERVICE_TOKEN" ] && [ "$SERVICE_TOKEN" != "null" ]; then
            break
          fi
          sleep 0.5
        done
        echo "Run agent: spire-agent run -config conf/agent/agent.conf -joinToken <token>"
        spire-agent run -config conf/agent/agent.conf -joinToken $SERVICE_TOKEN &
        trap 'kill $(jobs -p)' EXIT # Ensure background processes are killed on shell exit
      '';

    };
  };
}
