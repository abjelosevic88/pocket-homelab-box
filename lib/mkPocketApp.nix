# Builds one Pocket app the same way its Dockerfile does: the React UI first, then the Go binary
# with that UI embedded from web/dist. Tools the app shells out to are put on its PATH by a wrapper.
{ lib, buildGo126Module, buildNpmPackage, makeWrapper }:

{ pname, version, src, vendorHash, npmDepsHash, title ? pname
, runtime ? [ ], wrap ? [ ], postInstall ? "", npmFlags ? [ ] }:

let
  web = buildNpmPackage {
    pname = "${pname}-web";
    inherit version npmDepsHash;
    src = "${src}/web";
    npmFlags = [ "--no-audit" "--no-fund" ] ++ npmFlags;
    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -r dist/. $out/
      runHook postInstall
    '';
  };
  wrapped = runtime != [ ] || wrap != [ ];
in
buildGo126Module {
  inherit pname version src vendorHash;
  subPackages = [ "cmd/${pname}" ];
  env.CGO_ENABLED = 0;
  ldflags = [ "-s" "-w" "-X main.version=${version}" ];

  nativeBuildInputs = lib.optional wrapped makeWrapper;

  preBuild = ''
    rm -rf web/dist
    mkdir -p web/dist
    cp -r ${web}/. web/dist/
  '';

  postInstall = postInstall + "\n" + lib.optionalString wrapped ''
    wrapProgram $out/bin/${pname} \
      ${lib.optionalString (runtime != [ ]) "--prefix PATH : ${lib.makeBinPath runtime}"} \
      ${lib.concatStringsSep " " wrap}
  '';

  # The apps' own CI runs the tests; here they would only slow the image build down.
  doCheck = false;

  # Downloading the Go modules does not need the UI.
  overrideModAttrs = _: { preBuild = ""; postInstall = ""; };

  passthru = { inherit web; };

  meta = {
    description = title;
    license = lib.licenses.mit;
    mainProgram = pname;
    platforms = lib.platforms.linux;
  };
}
