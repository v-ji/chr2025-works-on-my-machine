{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      forAllSystems =
        function:
        nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed (
          system: function nixpkgs.legacyPackages.${system}
        );
      pythonDeps =
        ps: with ps; [
          jupyter
          pypdf
          polars
          beautifulsoup4
          requests
          tqdm
          pandas
          pyarrow
        ];
      getPythonEnv = pkgs: pkgs.python3.withPackages pythonDeps;
    in
    {
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            (getPythonEnv pkgs)

            # Utility script to clear notebook outputs and update requirements.txt before committing
            (pkgs.writeShellScriptBin "pre-commit" ''
              set -e
              echo "Clearing notebook outputs..."
              jupyter nbconvert --clear-output --inplace *.ipynb

              echo "Updating requirements.txt..."
              nix build '.#requirements' --quiet
              install -m 644 result/requirements.txt .

              echo "Done! Ready to commit."
            '')
          ];
        };
      });

      packages = forAllSystems (pkgs: {
        default = pkgs.stdenv.mkDerivation {
          name = "chr2025-works-on-my-machine";
          version = "1.0.0";
          src = ./.;

          buildInputs = [ (getPythonEnv pkgs) ];
          buildPhase = ''
            for nb in "get_papers.ipynb" "evaluation.ipynb"; do
              echo "Executing $nb..."

              out_dir="outputs/jupyter"
              out_file=$(basename $nb ".ipynb").ipynb

              jupyter nbconvert \
                --to notebook \
                --execute \
                --ClearMetadataPreprocessor.enabled=True \
                --output-dir $out_dir \
                --output $out_file \
                $nb

              echo "Rendering $nb to HTML..."

              jupyter nbconvert \
                --output-dir $out_dir \
                --to html \
                $out_dir/$out_file
            done
          '';

          installPhase = ''
            cp -r outputs $out
          '';
        };

        dockerShell = pkgs.dockerTools.buildNixShellImage rec {
          drv = self.packages.${pkgs.system}.default;
          tag = drv.version or null;
        };

        requirements = pkgs.stdenv.mkDerivation {
          name = "requirements-txt";
          buildInputs = [
            (getPythonEnv pkgs)
            pkgs.python3Packages.pip
          ];
          dontUnpack = true;
          buildCommand = ''
            mkdir -p $out
            echo "Writing requirements.txt for non-Nix users..."
            echo "# requirements.txt is provided on a best-effort basis." > $out/requirements.txt
            echo "# Please use Nix for a fully reproducible environment." >> $out/requirements.txt
            pip freeze >> $out/requirements.txt
          '';
        };
      });
    };
}
