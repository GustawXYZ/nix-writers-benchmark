{
  description = "Benchmark all Nix writers for startup performance";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f {
        inherit system;
        pkgs = nixpkgs.legacyPackages.${system};
      });
    in
    {
      packages = forAllSystems ({ system, pkgs }:
        let
          # Create test scripts for each writer
          testScripts = with pkgs; {
            bash = writers.writeBash "test-bash" "pwd";
            dash = writers.writeDash "test-dash" "pwd";
            fish = writers.writeFish "test-fish" "pwd";
            nu = writers.writeNu "test-nu" "pwd";
            nu-with-config = writeShellScript "test-nu-with-config" "${nushell}/bin/nu -c 'pwd'";

            # Python variants
            python3 = writers.writePython3 "test-python3" { } ''
              import os
              print(os.getcwd())
            '';
            pypy3 = writers.writePyPy3 "test-pypy3" { } ''
              import os
              print(os.getcwd())
            '';

            # Other languages
            lua = writers.writeLua "test-lua" { } "print(os.getenv('PWD'))";
            perl = writers.writePerl "test-perl" { } "use Cwd; print getcwd();";
            ruby = writers.writeRuby "test-ruby" { } "puts Dir.pwd";

            # Functional languages (where available)
            guile = writers.writeGuile "test-guile" { } "(display (getcwd))";
            babashka = writers.writeBabashka "test-babashka" { } "(println (System/getProperty \"user.dir\"))";

            # Compiled languages for comparison
            rust = writers.writeRust "test-rust" { } ''
              fn main() {
                  println!("{}", std::env::current_dir().unwrap().display());
              }
            '';
            haskell = writers.writeHaskell "test-haskell" { } ''
              import System.Directory
              main = getCurrentDirectory >>= putStrLn
            '';
          };

          benchmarkScript = pkgs.writers.writeNu "benchmark-writers" ''
            #!/usr/bin/env nu
            let iterations = 100
            print $"Benchmarking Nix writers startup times with ($iterations) iterations each...\n"
            # Define test scripts
            let test_scripts = {
              "bash": "${testScripts.bash}",
              "dash": "${testScripts.dash}",
              "fish": "${testScripts.fish}",
              "nu (no-config)": "${testScripts.nu}",
              "nu (with-config)": "${testScripts.nu-with-config}",
              "python3": "${testScripts.python3}",
              "pypy3": "${testScripts.pypy3}",
              "lua": "${testScripts.lua}",
              "perl": "${testScripts.perl}",
              "ruby": "${testScripts.ruby}",
              "guile": "${testScripts.guile}",
              "babashka": "${testScripts.babashka}",
              "rust": "${testScripts.rust}",
              "haskell": "${testScripts.haskell}"
            }
            # items is parallel, so we should accumulate the results
            let results = $test_scripts | items { |script_name, script_path|
              print $"Testing ($script_name)..."
              let time_result = (timeit {
                  for _ in 1..$iterations {
                    run-external $script_path | ignore
                  }
                })
              [["name", "time"]; [$script_name, $time_result]]
            } | flatten
            # and only then print them, to not have the split
            print $results
          '';

        in
        {
          benchmark = benchmarkScript;
          default = benchmarkScript;

          # Individual test scripts for manual testing
        } // testScripts
      );

      apps = forAllSystems ({ system, pkgs }: {
        benchmark = {
          type = "app";
          program = "${self.packages.${system}.benchmark}";
        };
        default = {
          type = "app";
          program = "${self.packages.${system}.benchmark}";
        };
      });

      devShells = forAllSystems ({ system, pkgs }: {
        default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nushell
            python3
            lua
            perl
            ruby
            guile
            babashka
            rustc
            ghc
            time
          ];
        };
      });
    };
}
