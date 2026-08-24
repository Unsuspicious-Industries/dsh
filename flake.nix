# USI DSH flake — one place that builds DeepSeek Harness from this fork and
# exposes everything a fleet needs to run it.
#
#   inputs.dsh.url = "github:Unsuspicious-Industries/dsh";
#   # then: imports = [ inputs.dsh.nixosModules.dsh ];
#   #       services.usi-dsh.enable = true;
#
# Why a flake here and not the old hash-discovery dance in the fleet repo:
# pkg.nix npm-installed the registry tarball, which worked only because the
# published package ships prebuilt lib/. A fork commit is SOURCE — building
# it means the full pnpm workspace (246 packages, native modules, patches),
# which cannot live behind one npm install. This flake owns that build in
# two stages:
#
#   1. dsh-deps      fixed-output: pnpm install --frozen-lockfile over the
#                    whole workspace (network allowed). Its hash pins the
#                    lockfile; it changes only when dependencies do.
#   2. dsh           offline build against the dep layer: pnpm build, then
#                    stage apps/cli + apps/web + every workspace lib into
#                    $out/lib/dsh the way the published @deepseek-ai/dsh
#                    package lays itself out (lib/bin.js entrypoint).
#
# Both stages are hash-discovered on first use (fakeHash) like pkg.nix was,
# but now the discovery lives next to the source it hashes.
{
  description = "DeepSeek Harness (USI fork) — bundle, checks, and NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        node = pkgs.nodejs_22;
        pnpm = pkgs.pnpm;

        src = self;

        # ── Stage 1: dependency layer ────────────────────────────────────
        # The entire pnpm virtual store, materialized once per lockfile.
        # Fixed-output because the install needs the network; the hash is
        # the ONLY thing downstream pins, so an unchanged lockfile means
        # this layer (and everything after it) comes from cache.
        deps = pkgs.stdenv.mkDerivation {
          pname = "dsh-deps";
          version = "0.1.1-rc.2";
          inherit src;

          nativeBuildInputs = [ node pkgs.cacert ];

          impureEnvVars = pkgs.lib.fetchers.proxyImpureEnvVars ++ [
            "NIX_SSL_CERT_FILE" "SSL_CERT_FILE" "npm_config_fetch_retries"
          ];

          dontPatchShebangs = true;

          buildPhase = ''
            export HOME=$TMPDIR
            export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            export SSL_CERT_FILE=$NIX_SSL_CERT_FILE
            export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
            # corepack resolves the packageManager-pinned pnpm (11.7.0) from
            # package.json; its store goes under $out so stage 2 reuses it.
            export PNPM_HOME=$TMPDIR/pnpm-home
            export PATH="$PNPM_HOME/bin:$PATH"
            export COREPACK_HOME=$TMPDIR/corepack
            corepack prepare $(node -e "console.log(require('./package.json').packageManager)")
            corepack pnpm config set store-dir $TMPDIR/store --global
            corepack pnpm install --frozen-lockfile
            # Park the corepack cache INSIDE the workspace so it rides
            # workspace.tar; stage 2 points COREPACK_HOME at it (offline).
            mkdir -p node_modules/.corepack-home
            cp -rT $TMPDIR/corepack node_modules/.corepack-home
          '';

          installPhase = ''
            mkdir -p $out
            # Ship the ENTIRE installed workspace (source + node_modules at
            # every level). Stage 2 then builds fully offline - no store
            # reuse, no corepack fetch, no supply-chain policy re-check.
            tar -cf $out/workspace.tar --exclude=.git .
            # Also ship the pnpm content-addressable store for the offline
            # reinstall stage 2 needs when it re-verifies node_modules.
            tar -cf $out/store.tar -C $TMPDIR store
          '';

          outputHashMode = "recursive";
          outputHashAlgo = "sha256";
          outputHash = builtins.readFile ./nix/deps-hash.txt;
        };
      in
      rec {
        packages.dsh = pkgs.stdenv.mkDerivation {
          pname = "dsh";
          version = "0.1.1-rc.2";
          inherit src;

          nativeBuildInputs = [ node pkgs.cacert pkgs.git ];

          dontPatchShebangs = true;

          configurePhase = ''
            export HOME=$TMPDIR
            export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
            export PNPM_HOME=$TMPDIR/pnpm-home
            export PATH="$PNPM_HOME/bin:$PATH"
            # Build scripts call `git rev-parse HEAD` for the version stamp;
            # provide a stable answer instead of a sandbox .git.
            mkdir -p $TMPDIR/bin
            printf '#!/bin/sh\n[ "$1" = rev-parse ] && { echo 54fbc14a1d; exit 0; }\nexit 1\n' > $TMPDIR/bin/git
            export DSH_CLIENT_COMMIT_HASH=54fbc14a1d
            chmod +x $TMPDIR/bin/git
            export PATH="$TMPDIR/bin:$PATH"
            export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            export SSL_CERT_FILE=$NIX_SSL_CERT_FILE
            export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
            # node_modules came pre-installed from the deps layer; stop pnpm
            # from re-verifying/reinstalling on every run invocation.
            export npm_config_verify_deps_before_run=false
            # Overlay the installed workspace (node_modules everywhere), but
            # keep THIS checkout's source authoritative: capture the clean
            # unpacked tree BEFORE the tar lands, then restore everything
            # except node_modules over the extracted (older) copy.
            mkdir -p $TMPDIR/pristine
            cp -rT . $TMPDIR/pristine
            rm -rf $TMPDIR/pristine/node_modules
            tar -xf ${deps}/workspace.tar
            tar -C $TMPDIR/pristine -cf - . | tar -xf - -C $PWD
            export COREPACK_HOME=$PWD/node_modules/.corepack-home
            mkdir -p "$COREPACK_HOME"
            # pnpm shim for anything that shells out to it during build.
            mkdir -p $TMPDIR/bin
            printf '#!/bin/sh\nexec corepack pnpm "$@"\n' > $TMPDIR/bin/pnpm
            chmod +x $TMPDIR/bin/pnpm
            export PATH="$TMPDIR/bin:$PWD/node_modules/.bin:$PATH"
            tar -xf ${deps}/store.tar -C $TMPDIR
            chmod -R u+w $TMPDIR/store
            export CI=true
            corepack pnpm config set store-dir $TMPDIR/store --global
            # minimumReleaseAge needs registry metadata; offline there is no
            # network, so every entry "fails" the age check. The lockfile was
            # already policy-checked during the online deps build. The
            # setting lives in pnpm-workspace.yaml, which outranks .npmrc,
            # so neutralise it there.
            grep -q '^minimumReleaseAge:' pnpm-workspace.yaml || \
              echo 'minimumReleaseAge: 0' >> pnpm-workspace.yaml
            corepack pnpm install --frozen-lockfile --offline
          '';

          buildPhase = ''
            # pnpm 11.7 ignores the npm_config spelling of this setting; an
            # .npmrc row is the reliable way to stop its auto-install pass.
            grep -q verify-deps-before-run .npmrc 2>/dev/null || \
              echo "verify-deps-before-run=false" >> .npmrc
            # Invoke the build script directly; `pnpm run` re-triggers its
            # deps-status check, which wants to reinstall. scripts/pnpm-
            # invocation.ts only needs npm_execpath to find pnpm for any
            # nested `pnpm <cmd>` calls - point it at the corepack shim.
            export npm_execpath=$PWD/node_modules/.corepack-home/v1/pnpm/11.7.0/bin/pnpm.mjs
            ./node_modules/.bin/tsx scripts/build.ts
          '';

          installPhase = ''
            mkdir -p $out/lib/dsh
            # Stage what bin.js needs at runtime: the CLI app with its built
            # lib/, plus every workspace package's lib/ under the same
            # relative layout, so workspace:* resolution walks real files.
            cp -rT apps/cli $out/lib/dsh
            mkdir -p $out/lib/dsh/node_modules/@deepseek-ai
            for pkgdir in packages/*/*/; do
              [ -f "$pkgdir/package.json" ] || continue
              name=$(node -e "console.log(require('./$pkgdir/package.json').name)" 2>/dev/null) || continue
              case "$name" in @deepseek-ai/*)
                target="$out/lib/dsh/node_modules/$name"
                mkdir -p "$(dirname "$target")"
                cp -rT "$pkgdir" "$target"
                chmod -R u+w "$target"
              ;; esac
            done
            for vendordir in vendor/*/; do
              [ -f "$vendordir/package.json" ] || continue
              name=$(node -e "console.log(require('./$vendordir/package.json').name)" 2>/dev/null) || continue
              target="$out/lib/dsh/node_modules/$name"
              mkdir -p "$(dirname "$target")"
              cp -rT "$vendordir" "$target"
              chmod -R u+w "$target"
            done
            chmod -R u+w $out/lib/dsh
          '';

          passthru = {
            inherit deps;
            # Compatibility with consumers still calling import ./pkg.nix.
            pkg = packages.dsh;
          };

          meta = with pkgs.lib; {
            description = "DeepSeek Harness — agent workbench (USI fork)";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        };

        packages.default = packages.dsh;

        checks.dsh-build = packages.dsh;

        devShells.default = pkgs.mkShell {
          packages = [ node pkgs.cacert ];
        };
      })
    // {
      # ── NixOS module ─────────────────────────────────────────────────────
      # Self-contained: brings its own package unless overridden.
      #
      #   services.usi-dsh = {
      #     enable = true;
      #     hostName = "dsh.unsuspicious.org";
      #     settingsTemplate = ./settings.yaml;   # with # FREOR_MODELS marker
      #     cordisPatch = ./cordis.patch.yml;
      #     credentialsScript = ./sync-credentials.js;  # opencode auth.json bridge
      #   };
      #
      # Sessions/state persist by construction: DSH_HOME lives in /var/lib/dsh
      # (a state directory no rebuild touches), and ExecStartPre installs are
      # idempotent copies, so `git push` deployments never lose sessions.
      nixosModules.dsh =
        { pkgs, config, lib, ... }:
        let
          cfg = config.services.usi-dsh;
          dshPkg = cfg.package;
          node = pkgs.nodejs_22;
          dshHome = "/var/lib/dsh";

          syncFreeModels = pkgs.writeScript "dsh-sync-free-models"
            ("#!${node}/bin/node\n" + lib.removePrefix "#!/usr/bin/env node\n" (builtins.readFile cfg.syncFreeModelsScript));

          syncCreds = pkgs.writeScript "dsh-sync-credentials"
            ("#!${node}/bin/node\n" + lib.removePrefix "#!/usr/bin/env node\n" (builtins.readFile cfg.syncCredentialsScript));

          # Restarts hand off to a transient unit: these scripts run inside
          # units in dsh-web's Requires= chain, so a synchronous restart
          # deadlocks (observed live: five hours of 502s).
          restartTrigger = ''
            if ${pkgs.systemd}/bin/systemctl is-active --quiet dsh-web.service; then
              ${pkgs.systemd}/bin/systemd-run --collect --unit=dsh-web-restart-trigger \
                ${pkgs.systemd}/bin/systemctl try-restart dsh-web.service
            fi
          '';
        in
        {
          options.services.usi-dsh = with lib; {
            enable = mkEnableOption "DSH agent workbench (web UI on :3080)";

            package = mkOption {
              type = types.package;
              default = self.packages.${pkgs.system}.dsh;
              defaultText = literalExpression "inputs.dsh.packages.\${pkgs.system}.dsh";
              description = "The DSH bundle to run.";
            };

            hostName = mkOption {
              type = types.str;
              default = "dsh.unsuspicious.org";
              description = "Trusted vhost served through the PAM gate.";
            };

            extraTrustedHosts = mkOption {
              type = types.listOf types.str;
              default = [ ];
              description = "Additional trusted-host values.";
            };

            settingsTemplate = mkOption {
              type = types.path;
              description = "settings.yaml template carrying the model-sync marker.";
            };

            syncFreeModelsScript = mkOption {
              type = types.path;
              description = "Node script pulling freor's /v1/models into settings.yaml.";
            };

            syncCredentialsScript = mkOption {
              type = types.path;
              description = "Node script exporting opencode auth.json to credentials.env.";
            };

            cordisPatch = mkOption {
              type = types.nullOr types.path;
              default = null;
              description = "Optional cordis.patch.yml installed into web+headless profiles.";
            };

            claudeCodeSubagent = mkOption {
              type = types.bool;
              default = false;
              description = "Symlink the Claude Code subagent plugin into both profiles.";
            };

            extraPathPackages = mkOption {
              type = types.listOf types.package;
              default = [ ];
              description = "Extra tools on dsh-web's PATH (bash/git already included).";
            };
          };

          config = lib.mkIf cfg.enable {
            systemd.services.dsh-state-prepare = {
              description = "Prepare DSH user state";
              before = [ "dsh-web.service" "dsh-credentials-sync.service" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                User = "root";
              };
              script = with pkgs; ''
                install -d -m 0700 -o dsh -g dsh ${dshHome}
                # Repair ownership after any root-run headless session: the
                # jsonl writer runs as dsh, and an EACCES here crashes boot.
                chown -R dsh:dsh ${dshHome}
              '';
            };

            systemd.services.dsh-credentials-sync = {
              description = "Re-export opencode credentials to dsh";
              after = [ "network-online.target" "dsh-state-prepare.service" ];
              requires = [ "dsh-state-prepare.service" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = pkgs.writeShellScript "dsh-sync-and-restart" ''
                  set -eu
                  PATH=${node}/bin:$PATH
                  ${syncCreds}
                  marker=/run/dsh-credentials-changed
                  rm -f "$marker"
                  DSH_CREDENTIALS_PATH=${dshHome}/credentials.env \
                    DSH_CREDENTIAL_CHANGE_MARKER="$marker" ${syncCreds}
                  ${pkgs.coreutils}/bin/chown dsh:dsh ${dshHome}/credentials.env
                  if [ -e "$marker" ]; then
                    rm -f "$marker"
                    ${restartTrigger}
                  fi
                '';
                # node must be findable: the unit replaces PATH.
                Environment = "PATH=${node}/bin:${pkgs.coreutils}/bin";
              };
            };
            systemd.timers.dsh-credentials-sync = {
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnCalendar = "*-*-* *:00:00";
                Persistent = true;
                Unit = "dsh-credentials-sync.service";
              };
            };

            systemd.services.dsh-free-models-sync = {
              description = "Synchronize DSH models from the unified door";
              after = [ "dsh-state-prepare.service" ];
              requires = [ "dsh-state-prepare.service" ];
              serviceConfig = {
                Type = "oneshot";
                ExecStart = pkgs.writeShellScript "dsh-sync-free-models-and-restart" ''
                  set -eu
                  PATH=${node}/bin:$PATH
                  marker=/run/dsh-free-models-changed
                  rm -f "$marker"
                  DSH_HOME=${dshHome} DSH_SETTINGS_CHANGE_MARKER="$marker" \
                    ${syncFreeModels} ${cfg.settingsTemplate}
                  ${pkgs.coreutils}/bin/chown dsh:dsh ${dshHome}/settings.yaml
                  if [ -e "$marker" ]; then
                    rm -f "$marker"
                    ${restartTrigger}
                  fi
                '';
                Environment = "PATH=${node}/bin:${pkgs.coreutils}/bin";
              };
            };
            systemd.timers.dsh-free-models-sync = {
              wantedBy = [ "timers.target" ];
              timerConfig = {
                OnBootSec = "1min";
                OnUnitActiveSec = "1min";
                Unit = "dsh-free-models-sync.service";
              };
            };

            systemd.services.dsh-web = {
              description = "DSH agent workbench (web UI)";
              wantedBy = [ "multi-user.target" ];
              after = [ "network-online.target" "dsh-state-prepare.service" "dsh-credentials-sync.service" ];
              requires = [ "dsh-state-prepare.service" "dsh-credentials-sync.service" ];
              path = [ pkgs.bash pkgs.git pkgs.coreutils pkgs.curl ] ++ cfg.extraPathPackages;
              serviceConfig = {
                Type = "simple";
                Restart = "on-failure";
                RestartSec = 5;
                User = "dsh";
                Group = "dsh";
                StateDirectory = "dsh";
                WorkingDirectory = "/workspace";
                ExecStart = lib.concatStringsSep " \\\n    " (
                  [
                    ''"${node}/bin/node --expose-internals ${dshPkg}/lib/dsh/lib/bin.js web"''
                    "--host 127.0.0.1 --port 3080"
                    "--trusted-host ${cfg.hostName}"
                  ] ++ map (h: "--trusted-host ${h}") cfg.extraTrustedHosts
                );
              };
              preStart = with pkgs; ''
                ${coreutils}/bin/install -D -m 0644 ${cfg.settingsTemplate} /tmp/dsh-settings-template.yaml
                ${lib.optionalString (cfg.cordisPatch != null)
                  "${coreutils}/bin/install -D -m 0644 ${cfg.cordisPatch} ${dshHome}/profiles/web/cordis.patch.yml\n${coreutils}/bin/install -D -m 0644 ${cfg.cordisPatch} ${dshHome}/profiles/headless/cordis.patch.yml"}
                ${lib.optionalString cfg.claudeCodeSubagent ''
                  ${coreutils}/bin/install -d ${dshHome}/profiles/web/node_modules/@deepseek-ai
                  ${coreutils}/bin/ln -sfn ${dshPkg}/lib/dsh/node_modules/@deepseek-ai/dsh-subagent-claude-code \
                    ${dshHome}/profiles/web/node_modules/@deepseek-ai/dsh-subagent-claude-code
                  ${coreutils}/bin/install -d ${dshHome}/profiles/headless/node_modules/@deepseek-ai
                  ${coreutils}/bin/ln -sfn ${dshPkg}/lib/dsh/node_modules/@deepseek-ai/dsh-subagent-claude-code \
                    ${dshHome}/profiles/headless/node_modules/@deepseek-ai/dsh-subagent-claude-code
                ''}
              '';
            };

            users.users."dsh" = lib.mkDefault {
              isNormalUser = true;
              uid = 1002;
              home = dshHome;
              useDefaultShell = true;
              description = "DSH service account";
            };
          };
        };

      overlays.dsh = final: prev: { dsh = self.packages.${final.system}.dsh; };
    };
}
