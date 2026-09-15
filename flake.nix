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
        deps = pkgs.fetchPnpmDeps {
          pname = "dsh-deps";
          version = "0.1.1-rc.2";
          src = self;
          # pnpm 11 rejects fetcher version 3 outright; 4 dumps the store's
          # SQLite index to SQL text so the hash does not depend on its binary
          # layout (nixpkgs#522703). Its fixup phase also deletes pnpm's
          # per-file `checkedAt` timestamps and archives with SOURCE_DATE_EPOCH
          # mtimes, so the fixed-output hash is pinnable.
          fetcherVersion = 4;
          hash = builtins.readFile ./nix/deps-hash.txt;
        };
      in
      rec {
        packages.dsh = pkgs.stdenv.mkDerivation {
          pname = "dsh";
          version = "0.1.1-rc.2";
          inherit src;

          nativeBuildInputs = [ node pkgs.cacert pkgs.git pkgs.pnpm pkgs.sqlite pkgs.zstd ];

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
            # stop pnpm re-verifying/reinstalling on every run invocation.
            export npm_config_verify_deps_before_run=false
            # The deps layer ships a pnpm store tarball, not an installed
            # workspace: this stage materializes node_modules itself, fully
            # offline, from the pinned store.
            mkdir -p $TMPDIR/store
            tar --zstd -xf ${deps}/pnpm-store.tar.zst -C $TMPDIR/store
            # Fetcher version 4 stores the v11 index as SQL text because the
            # binary form is not reproducible (nixpkgs#522703); rebuild the
            # index file pnpm reads.
            # The fetcher ships the store read-only (directories 555, files
            # 444), so make it writable before writing the rebuilt index.
            chmod -R u+w $TMPDIR/store
            if [ -f $TMPDIR/store/v11/index.db.sql ]; then
              sqlite3 $TMPDIR/store/v11/index.db < $TMPDIR/store/v11/index.db.sql
            fi
            export PATH="$PWD/node_modules/.bin:$PATH"
            export CI=true
            # package.json pins pnpm 11.7.0 while nixpkgs provides a newer one,
            # so pnpm tries to download the pinned release; there is no network
            # here. Ignore the mismatch and run the provided pnpm, exactly as
            # the deps fetcher does when it populates the store.
            export pnpm_config_pm_on_fail=ignore
            # The nixpkgs node ships corepack shims named `pnpm`, which shadow
            # pkgs.pnpm on PATH and try to download the pinned 11.7.0 release.
            # Call the provided pnpm by absolute path instead.
            export PNPM_BIN=${pkgs.pnpm}/bin/pnpm
            # package.json pins pnpm 11.7.0; corepack honours that field by
            # downloading the release, which needs a network this build has no
            # access to. Ignore the pin and use the provided pnpm.
            export COREPACK_ENABLE_PROJECT_SPEC=0
            "$PNPM_BIN" config set store-dir $TMPDIR/store --global
            # minimumReleaseAge needs registry metadata; offline there is no
            # network, so every entry "fails" the age check. The lockfile was
            # already policy-checked during the online deps build. The
            # setting lives in pnpm-workspace.yaml, which outranks .npmrc,
            # so neutralise it there.
            grep -q '^minimumReleaseAge:' pnpm-workspace.yaml || \
              echo 'minimumReleaseAge: 0' >> pnpm-workspace.yaml
            "$PNPM_BIN" install --frozen-lockfile --offline
          '';

          buildPhase = ''
            # pnpm 11.7 ignores the npm_config spelling of this setting; an
            # .npmrc row is the reliable way to stop its auto-install pass.
            grep -q verify-deps-before-run .npmrc 2>/dev/null || \
              echo "verify-deps-before-run=false" >> .npmrc
            # Invoke the build script directly; `pnpm run` re-triggers its
            # deps-status check, which wants to reinstall. scripts/pnpm-
            # invocation.ts only needs npm_execpath to find pnpm for any
            # nested `pnpm <cmd>` calls - resolve it to the nixpkgs pnpm the
            # store was fetched with.
            export npm_execpath=$(readlink -f $PNPM_BIN)
            # The build revision stays available for diagnostics, while the
            # product surface names this deployment rather than upstream.
            export DSH_CLIENT_TITLE='Unsuspicious DSH'
            ./node_modules/.bin/tsx scripts/build.ts
            # The web UI's dist is workspace knowledge: build the frontend
            # into apps/web/dist (dsh-web-app resolves it from there).
            corepack pnpm run build:web
          '';

          installPhase = ''
            mkdir -p $out/lib/dsh
            # Keep the full built workspace layout. pnpm's workspace and
            # .pnpm links are relative to this root; moving selected packages
            # into one flat node_modules tree broke transitive dependencies
            # and made dsh-web crash-loop on startup.
            tar -cf - --exclude=.git . | tar -xf - -C $out/lib/dsh
            chmod -R u+w $out/lib/dsh
            mkdir -p $out/bin
            cat > $out/bin/dsh <<EOF
            #!${pkgs.runtimeShell}
            exec ${node}/bin/node --expose-internals $out/lib/dsh/apps/cli/lib/bin.js "\$@"
            EOF
            chmod +x $out/bin/dsh
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
                    ${pkgs.util-linux}/bin/logger -t dsh-sync "credentials updated; will apply on next dsh-web restart"
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
                    ${pkgs.util-linux}/bin/logger -t dsh-sync "model catalog updated; will apply on next dsh-web restart"
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
                    ''"${dshPkg}/bin/dsh web"''
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
