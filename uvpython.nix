{
  pkgs,
  python,
  pyproject-nix,
  uv2nix,
  pyproject-build-systems,
  workspaceRoot,
  envName ? "venv",
  ...
}:
let
  # Common overrides that apply regardless of CUDA support
  commonOverrides =
    final: prev:
    let
      buildSystemOverrides = {
        nats-py.setuptools = [ ];
        antlr4-python3-runtime.setuptools = [ ];
        fairseq.setuptools = [ ];
        fairseq.numpy = [ ];
        fairscale.setuptools = [ ];
        docopt.setuptools = [ ];
        pyahocorasick.setuptools = [ ];
        phunspell.setuptools = [ ];
        unicodecsv.setuptools = [ ];
        fastcoref.setuptools = [ ];
        nvidia-ml-py3.setuptools = [ ];
        sox.setuptools = [ ];
        uuid.setuptools = [ ];
        argbind.setuptools = [ ];
        julius.setuptools = [ ];
        randomname.setuptools = [ ];
        crcmod.setuptools = [ ];
        jieba.setuptools = [ ];
        deepspeed.setuptools = [ ];
        aliyun-python-sdk-core.setuptools = [ ];
        phone-inventory-metric.uv-build = [ ];
        ci-sdr.setuptools = [ ];
        distance.setuptools = [ ];
        fast-bss-eval.setuptools = [ ];
        pyworld.cython = [ ];
        pyworld.wheel = [ ];
        pyworld.setuptools = [ ];
        pyworld.numpy = [ ];
        editdistance = {
          pdm-backend = [ ];
          cython = [ ];
          setuptools = [ ];
        };
      };
    in
    builtins.mapAttrs (
      name: spec:
      prev.${name}.overrideAttrs (old: {
        nativeBuildInputs = old.nativeBuildInputs ++ final.resolveBuildSystem spec;
      })
    ) buildSystemOverrides
    // {
      pyaudio = prev.pyaudio.overrideAttrs (old: {
        buildInputs = with pkgs; [ portaudio ] ++ (old.buildInputs or [ ]);
        nativeBuildInputs =
          (old.nativeBuildInputs or [ ])
          ++ final.resolveBuildSystem {
            setuptools = [ ];
          };
      });
      numba = prev.numba.overrideAttrs (old: {
        buildInputs = with pkgs; [
          gomp
        ];
        autoPatchelfIgnoreMissingDeps = [
          "libtbb.so.12"
        ];
      });
      # transformers - needs specific overrides for macOS/MPS
      transformers = prev.transformers.overrideAttrs (old: {
        nativeBuildInputs =
          (old.nativeBuildInputs or [ ]) ++ final.resolveBuildSystem { setuptools = [ ]; };
      });
      soundfile = prev.soundfile.overrideAttrs (_: {
        postInstall = ''
          substituteInPlace $out/lib/python*/site-packages/soundfile.py --replace "_find_library('sndfile')" "'${pkgs.libsndfile.out}/lib/libsndfile${pkgs.stdenv.hostPlatform.extensions.sharedLibrary}'"
        '';
      });
    };

  # Combine overrides based on platform and support flags
  pyprojectOverrides = pkgs.lib.composeManyExtensions [
    commonOverrides
  ];

  workspace = uv2nix.lib.workspace.loadWorkspace { inherit workspaceRoot; };
  pythonSet =
    (pkgs.callPackage pyproject-nix.build.packages {
      inherit python;
    }).overrideScope
      (
        pkgs.lib.composeManyExtensions [
          pyproject-build-systems.overlays.default
          (workspace.mkPyprojectOverlay {
            # Prefer wheels to avoid build dependency issues
            sourcePreference = "wheel";
          })
          pyprojectOverrides
        ]
      );
  venv = (pythonSet.mkVirtualEnv envName workspace.deps.default).overrideAttrs (old: {
    venvIgnoreCollisions = [
      "*bin/fastapi"
      "*site-packages/retry/*"
    ];
  });
in
venv
